# Native window placement uses Windows' own monitor/work-area correction when
# restoring a window after a monitor was removed or its resolution changed.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AccountManagerPlacement {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Placement {
        public int Length, Flags, ShowCommand;
        public Point MinPosition, MaxPosition;
        public Rect NormalPosition;
    }
    [DllImport("user32.dll")] private static extern bool GetWindowPlacement(IntPtr hwnd, ref Placement placement);
    [DllImport("user32.dll")] private static extern bool SetWindowPlacement(IntPtr hwnd, ref Placement placement);
    public static Placement Read(IntPtr hwnd) {
        var placement = new Placement();
        placement.Length = Marshal.SizeOf(typeof(Placement));
        if (!GetWindowPlacement(hwnd, ref placement)) throw new InvalidOperationException("Cannot read window placement.");
        return placement;
    }
    public static void Restore(IntPtr hwnd, int left, int top, int right, int bottom, bool maximized) {
        var placement = Read(hwnd);
        placement.Flags = 0;
        placement.ShowCommand = maximized ? 3 : 1;
        placement.NormalPosition = new Rect { Left = left, Top = top, Right = right, Bottom = bottom };
        if (!SetWindowPlacement(hwnd, ref placement)) throw new InvalidOperationException("Cannot restore window placement.");
    }
}
'@

function Save-ManagerWindowState {
    param([IntPtr]$Handle, [string]$Path)
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $placement = [AccountManagerPlacement]::Read($Handle)
        $bounds = $placement.NormalPosition
        # WPF/Windows preserves the restore-to-maximized flag when minimized.
        $maximized = $placement.ShowCommand -eq 3 -or (($placement.Flags -band 2) -ne 0)
        $state = [ordered]@{
            version=1; left=$bounds.Left; top=$bounds.Top; right=$bounds.Right; bottom=$bounds.Bottom
            maximized=$maximized
        }
        [IO.File]::WriteAllText($temporary, ($state | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
        return $true
    } catch { return $false }
    finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Restore-ManagerWindowState {
    param([IntPtr]$Handle, [string]$Path)
    try {
        if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
        $state = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        if ($state.version -ne 1 -or $state.maximized -isnot [bool]) { return $false }
        foreach ($name in @('left','top','right','bottom')) {
            if ($null -eq $state.$name -or [double]::IsNaN([double]$state.$name) -or [Math]::Abs([double]$state.$name) -gt 1000000) { return $false }
        }
        if (($state.right - $state.left) -lt 200 -or ($state.bottom - $state.top) -lt 150) { return $false }
        [AccountManagerPlacement]::Restore($Handle, $state.left, $state.top, $state.right, $state.bottom, $state.maximized)
        return $true
    } catch { return $false }
}
