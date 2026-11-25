[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
foreach ($script in @('agy-auth\Account-Manager.ps1','agy-auth\Verify-WindowState.ps1','agy-auth\Verify-Deployment.ps1')) {
    $arguments = @('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $script))
    if ($script -eq 'agy-auth\Account-Manager.ps1') { $arguments += '-SelfTest' }
    & $ps @arguments
    if ($LASTEXITCODE) { throw "Verification failed: $script" }
}
& (Join-Path $PSScriptRoot 'launcher\Build-Launcher.ps1')
$quiet = Start-Process -FilePath (Join-Path $PSScriptRoot 'launcher\AntigravityLauncher.exe') -ArgumentList 'self-test' -WindowStyle Hidden -PassThru
if (!$quiet.WaitForExit(15000) -or $quiet.ExitCode -ne 0) { throw 'Windowless launch verification failed.' }
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$testPath = Join-Path $PSScriptRoot 'launcher\Verify-ProcessCompletion.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /main:VerifyProcessCompletion /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "/out:$testPath" (Join-Path $PSScriptRoot 'launcher\AntigravityLauncher.cs') (Join-Path $PSScriptRoot 'launcher\Verify-ProcessCompletion.cs')
if ($LASTEXITCODE) { throw 'Completion regression build failed.' }
$check = Start-Process -FilePath $testPath -WindowStyle Hidden -PassThru
if (!$check.WaitForExit(20000) -or $check.ExitCode -ne 0) { throw 'Completion regression failed; inspect launcher/completion-verification.txt.' }
Get-Content -LiteralPath (Join-Path $PSScriptRoot 'launcher\completion-verification.txt')
Write-Output 'WINDOWS_WRAPPER_VERIFICATION_OK'
