$ErrorActionPreference = 'Stop'
$script:DeploymentRoot = $PSScriptRoot
$script:SourceRoot = Join-Path $PSScriptRoot 'source'
if (!(Test-Path -LiteralPath (Join-Path $script:SourceRoot 'go.mod'))) { $script:SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')) }
$script:Settings = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:AuthBinary = Join-Path $PSScriptRoot 'bin\agy-auth.exe'
$env:AGY_AUTH_HOME = Join-Path $PSScriptRoot 'private\accounts'
$env:AGY_AUTH_AGY_PATH = $script:Settings.agyBinary
$env:AGY_DESKTOP_BIN = $script:Settings.desktopBinary
$env:AGY_AUTH_NO_UPDATE_CHECK = '1'

function ConvertTo-NativeArgument([string]$Value) {
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function New-AuthProcess {
    param([string[]]$Arguments, [hashtable]$Environment = @{})
    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = $script:AuthBinary
    $processInfo.Arguments = (@('--json') + $Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $processInfo.WorkingDirectory = $script:DeploymentRoot
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.RedirectStandardInput = $true
    $processInfo.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $processInfo.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    foreach ($entry in $Environment.GetEnumerator()) { $processInfo.EnvironmentVariables[$entry.Key] = $entry.Value }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $processInfo
    if (!$process.Start()) { throw '无法启动 agy-auth。' }
    return $process
}

function Invoke-AuthJson {
    param([string[]]$Arguments, [hashtable]$Environment = @{})
    $process = New-AuthProcess -Arguments $Arguments -Environment $Environment
    try {
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(60000)) {
            $process.Kill()
            throw '操作超时。若刚才正在切号，请刷新列表并核对客户端状态。'
        }
        $output = $outputTask.GetAwaiter().GetResult()
        $null = $errorTask.GetAwaiter().GetResult()
        try { $envelope = $output | ConvertFrom-Json } catch { throw 'agy-auth 未返回可识别的结果。请运行一键更新或检查客户端路径。' }
        if ($process.ExitCode -ne 0 -or $envelope.error) {
            throw ($envelope.error.message + "`r`n" + $envelope.error.hint)
        }
        return $envelope.data
    } finally { $process.Dispose() }
}

function Get-AuthAccounts {
    Invoke-AuthJson -Arguments @('list', '--no-sync', '--no-usage')
}

function Resolve-AuthProfile([string]$Profile) {
    $data = Get-AuthAccounts
    $matches = @($data.accounts | Where-Object { $_.id -eq $Profile -or $_.alias -eq $Profile })
    if ($matches.Count -ne 1) { throw "没有找到唯一的配置：$Profile。请在账号管理窗口添加账号或设置别名。" }
    return $matches[0]
}

function Start-OfficialDesktop {
    if (!(Test-Path -LiteralPath $script:Settings.desktopBinary -PathType Leaf)) { throw '未找到 Antigravity 客户端，请修改 settings.json 中的 desktopBinary。' }
    Start-Process -FilePath $script:Settings.desktopBinary -ArgumentList '--remote-debugging-port=0'
}

function Switch-AuthProfile([string]$Profile) {
    if ($Profile -ne '-') { $null = Resolve-AuthProfile $Profile }
    $result = Invoke-AuthJson -Arguments @('switch', '--target=all', '--close-desktop', $Profile)
    if (!$result.cli_switched -or !$result.desktop_switched) {
        throw '凭据可能已更新，但客户端同步没有完整完成。请刷新列表并核对状态，勿连续重复切换。'
    }
    $current = (Get-AuthAccounts).current
    if (!$current -or $current.id -ne $result.account.id) { throw '切换后核对的账号与目标配置不一致。' }
    Start-OfficialDesktop
    return $result.account
}

function Remove-LoginWorkspace([string]$Path) {
    $allowed = [IO.Path]::GetFullPath((Join-Path $script:DeploymentRoot 'private\login')) + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath($Path)
    if (!$resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw '拒绝清理登录目录以外的路径。' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
