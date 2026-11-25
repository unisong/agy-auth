[CmdletBinding()]
param([string]$Binary)

. (Join-Path $PSScriptRoot 'Common.ps1')
if ($Binary) { $script:AuthBinary = [IO.Path]::GetFullPath($Binary) }
$checkRoot = Join-Path (Join-Path $PSScriptRoot 'private\login') ('check-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $checkRoot -Force | Out-Null
$environment = @{
    AGY_AUTH_HOME=(Join-Path $checkRoot 'accounts'); AGY_AUTH_STORAGE='file'
    AGY_AUTH_AGY_TOKEN_FILE=(Join-Path $checkRoot 'active-token')
    AGY_AUTH_DESKTOP_TOKEN_FILE=(Join-Path $checkRoot 'desktop-token')
    AGY_DESKTOP_HOME=(Join-Path $checkRoot 'desktop'); AGY_DESKTOP_DATA_DIR=(Join-Path $checkRoot 'desktop-data')
    AGY_DESKTOP_BIN=(Join-Path $checkRoot 'no-client.exe')
}
try {
    $fixture = Join-Path $script:SourceRoot 'harness\fixtures\credential.consumer.json'
    $null = Invoke-AuthJson -Arguments @('import',$fixture,'--alias','fixture-pro') -Environment $environment
    $null = Invoke-AuthJson -Arguments @('import',$fixture,'--alias','fixture-cloud','--gcp','--project','fixture-cloud-project','--region','global') -Environment $environment
    $accounts = Invoke-AuthJson -Arguments @('list','--no-sync','--no-usage') -Environment $environment
    if (@($accounts.accounts).Count -ne 2) { throw '同一邮箱的订阅与 Cloud 配置没有保持独立。' }
    $result = Invoke-AuthJson -Arguments @('switch','--target=cli','fixture-cloud') -Environment $environment
    if (!$result.cli_switched -or $result.account.auth_method -ne 'gcp' -or $result.account.project_id -ne 'fixture-cloud-project') { throw 'Cloud 配置切换检查失败。' }
    $settingsPath = Join-Path $checkRoot 'settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ($settings.gcp.project -ne 'fixture-cloud-project' -or $settings.gcp.location -ne 'global') { throw 'Cloud 项目与地区同步检查失败。' }
    $result = Invoke-AuthJson -Arguments @('switch','--target=cli','fixture-pro') -Environment $environment
    if (!$result.cli_switched -or $result.account.auth_method -ne 'consumer') { throw '订阅配置切换检查失败。' }
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ($settings.gcp) { throw '切回订阅时没有清除 Cloud 项目设置。' }
    $snapshot = Get-ChildItem -LiteralPath (Join-Path $checkRoot 'accounts\accounts') -Filter '*.json' -File | Select-Object -First 1
    if (![IO.File]::ReadAllText($snapshot.FullName).StartsWith('agy-auth-encrypted:v1:')) { throw '账号快照没有使用加密格式。' }
    $null = Invoke-AuthJson -Arguments @('switch','--target=cli','-') -Environment $environment
    Write-Output 'WINDOWS_ISOLATED_PROFILE_SWITCH_OK'
} finally { Remove-LoginWorkspace $checkRoot }
