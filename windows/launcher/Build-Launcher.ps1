$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$target = Join-Path $PSScriptRoot 'AntigravityLauncher.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "/out:$target" (Join-Path $PSScriptRoot 'AntigravityLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher build failed.' }
Write-Output 'WINDOWLESS_LAUNCHER_BUILD_OK'
