[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$root = $PSScriptRoot
$repo = Join-Path $root 'source'
if (!(Test-Path -LiteralPath (Join-Path $repo 'go.mod'))) { $repo = [IO.Path]::GetFullPath((Join-Path $root '..\..')) }
$go = Join-Path $root 'toolchain\go\bin\go.exe'
if (!(Test-Path -LiteralPath $go)) { $go = (Get-Command go.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
$git = (Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$lock = $null

function Invoke-SourceGit([string[]]$Arguments) {
    $output = & $git -C $repo @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git 操作失败：$($Arguments -join ' ')" }
    return $output
}

try {
    $origin = (Invoke-SourceGit @('remote','get-url','origin') | Select-Object -First 1).Trim()
    if ($origin.TrimEnd('/') -ne 'https://github.com/unisong/agy-auth.git') { throw '源码 origin 与你的 fork 不一致，更新停止。' }
    $branch = (Invoke-SourceGit @('branch','--show-current') | Select-Object -First 1).Trim()
    if ($branch -ne 'main') { throw '当前不是 main 分支，更新停止。' }
    & $git -C $repo diff --quiet HEAD --
    if ($LASTEXITCODE -ne 0 -or @(Invoke-SourceGit @('ls-files','--others','--exclude-standard')).Count) { throw '源码有本地修改，请先处理后再更新。' }
    if (!(Test-Path -LiteralPath $go -PathType Leaf)) { throw '本目录的 Go 编译工具不存在。' }
    if ($CheckOnly) { Write-Output 'FORK_UPDATE_CONFIGURATION_OK'; return }
    $lock = [IO.File]::Open((Join-Path $root 'private\.update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    Write-Host '正在同步你的 GitHub fork…'
    Invoke-SourceGit @('fetch','--prune','origin') | Out-Null
    Invoke-SourceGit @('merge','--ff-only','origin/main') | Out-Null
    $env:PATH = (Split-Path -Parent $go) + [IO.Path]::PathSeparator + $env:PATH
    $env:GOCACHE = Join-Path $root 'toolchain\build-cache'
    $env:GOMODCACHE = Join-Path $root 'toolchain\module-cache'
    $env:CGO_ENABLED = '0'
    Push-Location $repo
    try {
        foreach ($check in @('lint','secrets','docs','contracts')) {
            & $go run ./cmd/harness $check
            if ($LASTEXITCODE -ne 0) { throw "源码 $check 检查没有通过，保留当前运行程序。" }
        }
        & $go vet ./...
        if ($LASTEXITCODE -ne 0) { throw 'Go vet 没有通过，保留当前运行程序。' }
        $version = (Get-Content -LiteralPath (Join-Path $repo 'package.json') -Raw | ConvertFrom-Json).version
        $stagedBinary = Join-Path $root 'bin\agy-auth.next.exe'
        & $go build -trimpath -ldflags "-s -w -X github.com/fikrilal/agy-auth/internal/cli.Version=$version" -o $stagedBinary ./cmd/agy-auth
        if ($LASTEXITCODE -ne 0) { throw '编译失败，保留当前运行程序。' }
        & (Join-Path $root 'Verify-Deployment.ps1') -Binary $stagedBinary
    } finally { Pop-Location }
    $target = [IO.Path]::GetFullPath((Join-Path $root 'bin\agy-auth.exe'))
    $stage = [IO.Path]::GetFullPath($stagedBinary)
    $allowed = [IO.Path]::GetFullPath((Join-Path $root 'bin')) + [IO.Path]::DirectorySeparatorChar
    if (!$target.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -or !$stage.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw '程序替换路径超出本目录。' }
    if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $root 'bin\agy-auth.previous.exe') -Force }
    Move-Item -LiteralPath $stage -Destination $target -Force
    $manifest = [ordered]@{ repository=$origin; commit=(Invoke-SourceGit @('rev-parse','HEAD') | Select-Object -First 1).Trim(); version=$version; binary_sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash; updated_at=[DateTimeOffset]::Now.ToString('o') }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'deployment.json') -Encoding UTF8
    Write-Host '更新完成。账号库、窗口和快捷入口均已保留。'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally { if ($lock) { $lock.Dispose() } }
