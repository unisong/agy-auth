$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, WindowsBase, System.Windows.Forms
. (Join-Path $PSScriptRoot 'Window-State.ps1')
$statePath = [IO.Path]::GetTempFileName()
$window = $null

function New-PlacementTestWindow {
    $form = New-Object Windows.Window
    $form.Title = '窗口布局验证'
    $form.ShowInTaskbar = $false
    $form.ShowActivated = $false
    $form.Width = 1040; $form.Height = 680
    $form.Left = 100; $form.Top = 100
    $form.Opacity = 0
    $form.Show()
    return $form
}

function Get-TestHandle($Window) { (New-Object Windows.Interop.WindowInteropHelper($Window)).Handle }
function Flush-TestLayout($Window) { $Window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::ApplicationIdle) }

try {
    $window = New-PlacementTestWindow
    Flush-TestLayout $window
    $handle = Get-TestHandle $window
    if (!(Save-ManagerWindowState -Handle $handle -Path $statePath)) { throw 'Save failed.' }
    $expected = [AccountManagerPlacement]::Read($handle).NormalPosition
    $window.Close()
    $window = New-PlacementTestWindow
    $window.Width = 900; $window.Height = 590
    $handle = Get-TestHandle $window
    if (!(Restore-ManagerWindowState -Handle $handle -Path $statePath)) { throw 'Restore failed.' }
    Flush-TestLayout $window
    $actual = [AccountManagerPlacement]::Read($handle).NormalPosition
    foreach ($name in @('Left','Top','Right','Bottom')) {
        if ($actual.$name -ne $expected.$name) { throw "Round-trip mismatch: $name" }
    }
    $window.WindowState = 'Maximized'
    Flush-TestLayout $window
    $null = Save-ManagerWindowState -Handle $handle -Path $statePath
    if (!(Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).maximized) { throw 'Maximized state was not saved.' }
    $window.Close()
    $window = New-PlacementTestWindow
    $handle = Get-TestHandle $window
    $null = Restore-ManagerWindowState -Handle $handle -Path $statePath
    Flush-TestLayout $window
    if ([AccountManagerPlacement]::Read($handle).ShowCommand -ne 3) { throw 'Maximized state was not restored.' }
    $window.WindowState = 'Normal'
    $window.WindowState = 'Minimized'
    Flush-TestLayout $window
    $null = Save-ManagerWindowState -Handle $handle -Path $statePath
    $null = Restore-ManagerWindowState -Handle $handle -Path $statePath
    Flush-TestLayout $window
    if ([AccountManagerPlacement]::Read($handle).ShowCommand -ne 1) { throw 'Minimized window did not restore visibly.' }
    '{"version":1,"left":90000,"top":90000,"right":91040,"bottom":90680,"maximized":false}' | Set-Content -LiteralPath $statePath -Encoding UTF8
    $null = Restore-ManagerWindowState -Handle $handle -Path $statePath
    Flush-TestLayout $window
    $bounds = [AccountManagerPlacement]::Read($handle).NormalPosition
    if ($bounds.Left -gt 80000 -or $bounds.Top -gt 80000) { throw 'Off-screen window was not corrected.' }
    '{broken json' | Set-Content -LiteralPath $statePath -Encoding UTF8
    if (Restore-ManagerWindowState -Handle $handle -Path $statePath) { throw 'Invalid state was accepted.' }
    Write-Output 'WINDOW_STATE_OK: size, position, maximized, minimized, off-screen correction, corrupt-file fallback'
} finally {
    if ($window) { $window.Close() }
    Remove-Item -LiteralPath $statePath -Force
}
