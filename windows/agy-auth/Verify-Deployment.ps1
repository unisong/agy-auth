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
    $saved = Invoke-AuthJson -Arguments @('list','--no-sync','--no-usage') -Environment $environment
    $pro = @($saved.accounts | Where-Object { $_.alias -eq 'fixture-pro' })[0]
    $cloud = @($saved.accounts | Where-Object { $_.alias -eq 'fixture-cloud' })[0]
    $liveHash = (Get-FileHash -LiteralPath $environment.AGY_AUTH_AGY_TOKEN_FILE).Hash
    $settingsHash = (Get-FileHash -LiteralPath $settingsPath).Hash
    $rejected = $false
    try { Set-SavedProfileAlias -ProfileId $pro.id -Alias 'FIXTURE-CLOUD' -Environment $environment }
    catch { if ($_.Exception.Message -notlike '*已被其他配置使用*') { throw }; $rejected = $true }
    if (!$rejected) { throw '重复别名未被拒绝。' }
    Set-SavedProfileAlias -ProfileId $pro.id -Alias '测试-pro' -Environment $environment
    $renamed = Invoke-AuthJson -Arguments @('list','--no-sync','--no-usage') -Environment $environment
    if (@($renamed.accounts | Where-Object { $_.id -ceq $pro.id -and $_.alias -ceq '测试-pro' }).Count -ne 1 -or $renamed.current.id -cne $cloud.id -or $renamed.current.alias -cne 'fixture-cloud') { throw '别名未持久化，或修改了同邮箱的其他配置。' }
    if ((Get-FileHash -LiteralPath $environment.AGY_AUTH_AGY_TOKEN_FILE).Hash -ne $liveHash -or (Get-FileHash -LiteralPath $settingsPath).Hash -ne $settingsHash) { throw '修改别名影响了当前凭据或设置。' }
    Write-Output 'WINDOWS_ISOLATED_PROFILE_ALIAS_OK'
    $rejected = $false
    try { $null = Remove-SavedProfile -ProfileId $pro.email -Environment $environment }
    catch { $rejected = $true }
    if (!$rejected) { throw '删除操作接受了邮箱而不是精确配置 ID。' }
    $null = Remove-SavedProfile -ProfileId $pro.id -Environment $environment
    $remaining = Invoke-AuthJson -Arguments @('list','--no-sync','--no-usage') -Environment $environment
    if (@($remaining.accounts).Count -ne 1 -or $remaining.accounts[0].id -ne $cloud.id) { throw '删除订阅配置误删了同邮箱的 Cloud 配置。' }
    $null = Remove-SavedProfile -ProfileId $cloud.id -Environment $environment
    $remaining = Invoke-AuthJson -Arguments @('list','--no-sync','--no-usage') -Environment $environment
    if (@($remaining.accounts).Count -ne 0 -or !$remaining.current -or $remaining.current.stored) { throw '删除当前配置后列表或当前登录状态不正确。' }
    if ($remaining.current.auth_method -ne 'gcp' -or $remaining.current.project_id -ne 'fixture-cloud-project') { throw '删除配置改变了当前计费模式。' }
    if ((Get-FileHash -LiteralPath $environment.AGY_AUTH_AGY_TOKEN_FILE).Hash -ne $liveHash -or (Get-FileHash -LiteralPath $settingsPath).Hash -ne $settingsHash) { throw '删除保存配置修改了当前凭据或设置。' }
    foreach ($id in @($pro.id,$cloud.id)) {
        if (Test-Path -LiteralPath (Join-Path $checkRoot "accounts\accounts\$id.json")) { throw '删除后仍保留对应账号快照。' }
    }
    $rejected = $false
    try { $null = Remove-SavedProfile -ProfileId $cloud.id -Environment $environment }
    catch { $rejected = $true }
    if (!$rejected) { throw '不存在的配置仍可被重复删除。' }
    Write-Output 'WINDOWS_ISOLATED_PROFILE_REMOVE_OK: exact ID, same-email isolation, live credential/settings retained, empty list, stale ID rejected'
} finally { Remove-LoginWorkspace $checkRoot }
