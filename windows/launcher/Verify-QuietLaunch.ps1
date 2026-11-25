$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class QuietLaunchProbe {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList([Out] uint[] ids, uint count);
}
'@
$consoleWindow = [QuietLaunchProbe]::GetConsoleWindow().ToInt64()
$ids = New-Object uint32[] 16
$consoleProcesses = [QuietLaunchProbe]::GetConsoleProcessList($ids, 16)
$nodeVersion = if (Get-Command node.exe -ErrorAction SilentlyContinue) { (& node.exe --version | Out-String).Trim() } else { 'not installed (optional)' }
$gitVersion = (& git.exe --version | Out-String).Trim()
$attachedIds = @($ids | Where-Object { $_ -ne 0 })
# CREATE_NO_WINDOW may retain a private console object for standard streams;
# it must have no HWND and must not share another interactive shell's console.
$result = [ordered]@{ consoleWindow=$consoleWindow; consoleProcesses=$consoleProcesses; attachedProcessIds=$attachedIds; processId=$PID; node=$nodeVersion; git=$gitVersion; passed=($consoleWindow -eq 0 -and @($attachedIds | Where-Object { $_ -ne $PID }).Count -eq 0); checkedAt=[DateTimeOffset]::Now.ToString('o') }
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'verification.json') -Encoding UTF8
if (!$result.passed) { throw 'The child PowerShell process has a window or shares an interactive console.' }
