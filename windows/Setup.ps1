[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AgyBinary,
    [Parameter(Mandatory=$true)][string]$DesktopBinary,
    [string]$GoBinary = 'go.exe'
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gui = Join-Path $PSScriptRoot 'agy-auth'
foreach ($path in @($AgyBinary, $DesktopBinary)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Application does not exist: $path" }
}
$go = (Get-Command $GoBinary -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$settingsPath = Join-Path $gui 'settings.json'
if (!(Test-Path -LiteralPath $settingsPath)) {
    $settings = [ordered]@{ agyBinary=[IO.Path]::GetFullPath($AgyBinary); desktopBinary=[IO.Path]::GetFullPath($DesktopBinary) }
    [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json), (New-Object Text.UTF8Encoding($true)))
}
$private = Join-Path $gui 'private'
New-Item -ItemType Directory -Path $private -Force | Out-Null
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
$acl.SetOwner($userSid)
foreach ($sid in @($userSid, $systemSid)) {
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $private -AclObject $acl
$bin = Join-Path $gui 'bin'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$version = (Get-Content -LiteralPath (Join-Path $repo 'package.json') -Raw | ConvertFrom-Json).version
$stagedBinary = Join-Path $bin 'agy-auth.next.exe'
Push-Location $repo
try {
    & $go build -trimpath -ldflags "-s -w -X github.com/fikrilal/agy-auth/internal/cli.Version=$version" -o $stagedBinary ./cmd/agy-auth
    if ($LASTEXITCODE) { throw 'Go build failed.' }
} finally { Pop-Location }
& (Join-Path $gui 'Verify-Deployment.ps1') -Binary $stagedBinary
$target = Join-Path $bin 'agy-auth.exe'
if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $bin 'agy-auth.previous.exe') -Force }
Move-Item -LiteralPath $stagedBinary -Destination $target -Force
& (Join-Path $PSScriptRoot 'launcher\Build-Launcher.ps1')
$launcher = Join-Path $PSScriptRoot 'launcher\AntigravityLauncher.exe'
$shell = New-Object -ComObject WScript.Shell
foreach ($entry in @(@('Account Manager.lnk','manager'),@('Update Tool.lnk','update-auth'))) {
    $shortcut = $shell.CreateShortcut((Join-Path $gui $entry[0]))
    $shortcut.TargetPath = $launcher
    $shortcut.Arguments = $entry[1]
    $shortcut.WorkingDirectory = $gui
    $shortcut.IconLocation = $DesktopBinary + ',0'
    $shortcut.Save()
}
Write-Output 'WINDOWS_SETUP_OK: open windows/agy-auth/Account Manager.lnk'
