[CmdletBinding()]
param([switch]$SelfTest)

. (Join-Path $PSScriptRoot 'Common.ps1')

# Set awareness before WPF creates windows, including when the host has already
# chosen process-level DPI settings. All dimensions in XAML are logical pixels.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AccountManagerDpi {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern IntPtr GetWindowDpiAwarenessContext(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
}
'@
[void][AccountManagerDpi]::SetProcessDpiAwarenessContext([IntPtr](-4))
[void][AccountManagerDpi]::SetThreadDpiAwarenessContext([IntPtr](-4))
[AppContext]::SetSwitch('Switch.System.Windows.DoNotScaleForDpiChanges', $false)
[AppContext]::SetSwitch('Switch.System.Windows.DoNotUsePresentationDpiCapabilityTier2OrGreater', $false)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $PSScriptRoot 'Window-State.ps1')

function New-ManagerWindow([string]$Name) {
    $path = Join-Path (Join-Path $PSScriptRoot 'ui') ($Name + '.xaml')
    $context = New-Object Windows.Markup.ParserContext
    $context.BaseUri = New-Object Uri($path)
    $reader = [IO.File]::OpenRead($path)
    try { $window = [Windows.Markup.XamlReader]::Load($reader, $context) }
    finally { $reader.Dispose() }
    if (Test-Path -LiteralPath $script:Settings.desktopBinary) {
        Add-Type -AssemblyName System.Drawing
        $icon = [Drawing.Icon]::ExtractAssociatedIcon($script:Settings.desktopBinary)
        if ($icon) {
            try { $window.Icon = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($icon.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()) }
            finally { $icon.Dispose() }
        }
    }
    return $window
}

function Show-OperationError($ErrorRecord) {
    if ($SelfTest) { throw $ErrorRecord.Exception }
    [void][Windows.MessageBox]::Show($script:MainForm, $ErrorRecord.Exception.Message, '操作未完成', 'OK', 'Warning')
}

function Request-AccountDetails {
    $dialog = New-ManagerWindow 'AccountDetails'
    $dialog.Owner = $script:MainForm
    $emailInput = $dialog.FindName('EmailInput')
    $aliasInput = $dialog.FindName('AliasInput')
    $projectInput = $dialog.FindName('ProjectInput')
    $cloudCheck = $dialog.FindName('CloudCheck')
    $validation = $dialog.FindName('ValidationMessage')
    $cloudCheck.Add_Checked({ $projectInput.IsEnabled = $true })
    $cloudCheck.Add_Unchecked({ $projectInput.IsEnabled = $false })
    $dialog.FindName('NextButton').Add_Click({
        $message = ''
        if ($emailInput.Text.Trim() -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { $message = '请填写要授权的邮箱。' }
        elseif ($aliasInput.Text.Trim() -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,39}$') { $message = '别名请使用 1–40 个英文字母、数字、点、下划线或短横线。' }
        elseif ($cloudCheck.IsChecked -and $projectInput.Text.Trim() -notmatch '^[a-z][a-z0-9-]{4,61}[a-z0-9]$') { $message = '请填写有效的 Google Cloud 项目 ID。' }
        if ($message) { $validation.Text = $message; $validation.Visibility = 'Visible'; return }
        $dialog.DialogResult = $true
    })
    $dialog.Add_ContentRendered({ [void]$emailInput.Focus() })
    if ($dialog.ShowDialog() -ne $true) { return $null }
    return [PSCustomObject]@{ Email=$emailInput.Text.Trim(); Alias=$aliasInput.Text.Trim(); Cloud=[bool]$cloudCheck.IsChecked; Project=$projectInput.Text.Trim() }
}

function New-RemoveProfileDialog($Account) {
    $dialog = New-ManagerWindow 'RemoveProfile'
    $dialog.Owner = $script:MainForm
    $dialog.FindName('ProfileEmail').Text = [string]$Account.email
    $mode = if ($Account.auth_method -eq 'gcp') { 'Cloud 按量计费' } else { 'Google 订阅模式' }
    $alias = if ($Account.alias) { $Account.alias } else { '未设置别名' }
    $details = "别名：$alias`r`n模式：$mode"
    if ($Account.auth_method -eq 'gcp') { $details += "`r`n项目：$($Account.project_id)`r`n地区：$($Account.region)" }
    $dialog.FindName('ProfileDetails').Text = $details
    if ($Account.active) { $dialog.FindName('CurrentNotice').Visibility = 'Visible' }
    $dialog.FindName('ConfirmRemoveButton').Add_Click({ param($sender, $eventArgs) [Windows.Window]::GetWindow($sender).DialogResult = $true })
    $dialog.Add_ContentRendered({ param($sender, $eventArgs) [void]$sender.FindName('CancelRemoveButton').Focus() })
    return $dialog
}

$script:NotesDirectory = if ($SelfTest) { Join-Path ([IO.Path]::GetTempPath()) ('agy-notes-test-' + [Guid]::NewGuid().ToString('N')) } else { Join-Path $script:DeploymentRoot 'private\profile-notes' }

function Get-ProfileNotePath([string]$ProfileId) {
    if ($ProfileId -cnotmatch '\A[a-zA-Z0-9_-]+\z') { throw '配置 ID 无效，请刷新列表。' }
    Join-Path $script:NotesDirectory ('note-' + $ProfileId + '.txt')
}

function Get-ProfileNote([string]$ProfileId) {
    $path = Get-ProfileNotePath $ProfileId
    if ([IO.File]::Exists($path)) { return [IO.File]::ReadAllText($path) }
    return ''
}

function Set-ProfileNote([string]$ProfileId, [string]$Note) {
    $path = Get-ProfileNotePath $ProfileId
    if ([string]::IsNullOrWhiteSpace($Note)) {
        if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
        return
    }
    $null = [IO.Directory]::CreateDirectory($script:NotesDirectory)
    $temp = Join-Path $script:NotesDirectory ([IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllText($temp, $Note)
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp, $path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp, $path) }
    } finally { [IO.File]::Delete($temp) }
}

function Edit-SelectedNote {
    $row = $list.SelectedItem
    if (!$row.Account.stored -or $script:Busy) { return }
    $dialog = New-ManagerWindow 'EditNote'
    $dialog.Owner = $script:MainForm
    $dialog.FindName('ProfileEmail').Text = $row.Email
    $dialog.FindName('ProfileDetails').Text = "$($row.Alias) · $($row.Mode) · $($row.Project)"
    $inputBox = $dialog.FindName('NoteInput')
    $inputBox.Text = $row.Note
    $dialog.Add_ContentRendered({ [void]$inputBox.Focus(); $inputBox.SelectAll() })
    $dialog.FindName('SaveNoteButton').Add_Click({ $dialog.DialogResult = $true })
    if ($dialog.ShowDialog() -ne $true) { return }
    $note = $inputBox.Text.Trim()
    Set-ProfileNote $row.Account.id $note
    $row.Note = $note
    $list.Items.Refresh()
}

function Remove-SelectedProfile {
    $account = Get-SelectedProfile
    if (!$account.stored) { throw '请选择已保存的配置。' }
    $dialog = New-RemoveProfileDialog $account
    if ($dialog.ShowDialog() -ne $true) { return }
    Run-UiOperation { $null = Remove-SavedProfile -ProfileId $account.id; Set-ProfileNote $account.id '' }
}

function Add-GoogleAccount($Details) {
    $loginDir = Join-Path (Join-Path $script:DeploymentRoot 'private\login') ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $loginDir -Force | Out-Null
    $tokenPath = Join-Path $loginDir 'oauth-token'
    $isolatedEnvironment = @{
        AGY_AUTH_HOME=(Join-Path $loginDir 'registry'); AGY_AUTH_STORAGE='file'; AGY_AUTH_AGY_TOKEN_FILE=$tokenPath
        AGY_DESKTOP_HOME=(Join-Path $loginDir 'desktop'); AGY_DESKTOP_DATA_DIR=(Join-Path $loginDir 'desktop-data')
        AGY_AUTH_DESKTOP_TOKEN_FILE=(Join-Path $loginDir 'desktop-token'); AGY_DESKTOP_BIN=(Join-Path $loginDir 'no-desktop.exe')
    }
    $arguments = @('login', '--no-browser', '--alias', $Details.Alias)
    if ($Details.Cloud) { $arguments += @('--gcp', '--project', $Details.Project, '--region', 'global') }
    $dialog = New-ManagerWindow 'GoogleAuthorization'
    $dialog.Owner = $script:MainForm
    $dialog.FindName('TargetEmail').Text = $Details.Email
    $instructions = $dialog.FindName('Instructions')
    $openButton = $dialog.FindName('OpenEdgeButton')
    $codeInput = $dialog.FindName('CodeInput')
    $submitButton = $dialog.FindName('SubmitButton')
    $process = New-AuthProcess -Arguments $arguments -Environment $isolatedEnvironment
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $oauthState = @{ Buffer=(New-Object char[] 4096); Text=''; ReadTask=$null; Error=$null }
    $oauthState.ReadTask = $process.StandardError.ReadAsync($oauthState.Buffer, 0, $oauthState.Buffer.Length)
    $script:OAuthUrl = $null
    $accepted = $false
    $openButton.Add_Click({
        $edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
        if (!(Test-Path -LiteralPath $edge)) { $edge = Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe' }
        if (Test-Path -LiteralPath $edge) { Start-Process -FilePath $edge -ArgumentList (ConvertTo-NativeArgument $script:OAuthUrl) }
        else { [void][Windows.MessageBox]::Show($dialog, '未找到 Edge。请安装 Edge 后再授权。', '无法打开浏览器') }
    })
    $submitButton.Add_Click({
        if (!$codeInput.Password.Trim()) { $instructions.Text = '请先粘贴 Google 页面显示的授权码。'; return }
        try {
            $process.StandardInput.WriteLine($codeInput.Password.Trim())
            $process.StandardInput.Flush()
            $codeInput.Clear()
            $submitButton.IsEnabled = $false
            $instructions.Text = '正在验证授权，成功后会自动返回账号列表…'
        } catch { $oauthState.Error = $_; $dialog.Close() }
    })
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        try {
            if ($oauthState.ReadTask.IsCompleted) {
                $count = $oauthState.ReadTask.GetAwaiter().GetResult()
                if ($count -gt 0) {
                    $oauthState.Text += New-Object string($oauthState.Buffer, 0, $count)
                    if (!$script:OAuthUrl -and $oauthState.Text -match 'https://accounts\.google\.com/[^\s]+') {
                        $script:OAuthUrl = $Matches[0]
                        $openButton.Content = '打开 Edge，选择目标 Google 账号'
                        $openButton.IsEnabled = $true
                    }
                    $oauthState.ReadTask = $process.StandardError.ReadAsync($oauthState.Buffer, 0, $oauthState.Buffer.Length)
                }
            }
            if ($process.HasExited) { $timer.Stop(); $dialog.DialogResult = $true }
        } catch { $oauthState.Error = $_; $timer.Stop(); $dialog.Close() }
    })
    try {
        $timer.Start()
        [void]$dialog.ShowDialog()
        if ($oauthState.Error) { throw $oauthState.Error }
        if (!$process.HasExited) { $process.Kill(); throw 'Google 授权已取消。当前客户端账号没有切换。' }
        $envelope = $outputTask.GetAwaiter().GetResult() | ConvertFrom-Json
        if ($process.ExitCode -ne 0 -or $envelope.error) { throw ($envelope.error.message + "`r`n" + $envelope.error.hint) }
        $metadata = Invoke-AuthJson -Arguments @('list', '--no-sync', '--no-usage') -Environment $isolatedEnvironment
        if (!$metadata.current -or $metadata.current.email -ne $Details.Email) {
            throw '实际授权邮箱与填写的目标邮箱不一致，未导入。请重新授权并切换到正确的 Google 账号。'
        }
        $null = Invoke-AuthJson -Arguments @('import', $tokenPath, '--alias', $Details.Alias)
        $accepted = $true
    } finally {
        $timer.Stop(); $codeInput.Clear()
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
        $script:OAuthUrl = $null
        $oauthState.Text = $null
        Remove-LoginWorkspace $loginDir
    }
    return $accepted
}

$script:MainForm = New-ManagerWindow 'Main'
$list = $script:MainForm.FindName('AccountList')
$script:Buttons = @('SwitchButton','PreviousButton','AddButton','SaveButton','RefreshButton','ShortcutButton','RemoveButton','EditNoteButton') | ForEach-Object { $script:MainForm.FindName($_) }
$script:Busy = $false

function Update-SelectionState {
    $selected = $list.SelectedItem
    $script:Buttons[0].IsEnabled = !$script:Busy -and $null -ne $selected
    $script:Buttons[5].IsEnabled = !$script:Busy -and $null -ne $selected
    $script:Buttons[6].IsEnabled = !$script:Busy -and $null -ne $selected -and $selected.Account.stored
    $script:Buttons[7].IsEnabled = $script:Buttons[6].IsEnabled
    $script:MainForm.FindName('SelectionHint').Text = $(if ($script:Busy) { '正在处理，请稍候…' } elseif ($selected) { '已选择：' + $selected.Alias } else { '请先选择一个配置' })
}

function Set-AccountList($Data) {
    $selectedId = if ($list.SelectedItem) { $list.SelectedItem.Account.id } else { $null }
    $rows = @(
        foreach ($account in @($Data.accounts)) {
            if (!$account) { continue }
            $cloud = $account.auth_method -eq 'gcp'
            [PSCustomObject]@{
                Account=$account; Email=[string]$account.email
                Note=$(if ($account.stored) { Get-ProfileNote $account.id } else { '' })
                Alias=$(if ($account.alias) { [string]$account.alias } else { '未设置别名' })
                Mode=$(if ($cloud) { 'Cloud 计费' } else { '订阅模式' })
                ModeBackground=$(if ($cloud) { '#EFF6FF' } else { '#F3EEFF' })
                ModeForeground=$(if ($cloud) { '#2563EB' } else { '#7C3AED' })
                Project=$(if ($cloud) { [string]$account.project_id } else { 'Google 账号订阅' })
                Region=$(if ($cloud) { [string]$account.region } else { '按账号权益使用' })
                Status=$(if ($account.active) { '当前' } else { '' })
            }
        }
    )
    $list.ItemsSource = $rows
    $selection = @($rows | Where-Object { $_.Account.id -eq $selectedId })
    if ($selection.Count -eq 0) { $selection = @($rows | Where-Object { $_.Account.active }) }
    if ($selection.Count -gt 0) { $list.SelectedItem = $selection[0] }
    $script:MainForm.FindName('AccountCount').Text = "$($rows.Count) 个"
    $script:MainForm.FindName('EmptyState').Visibility = $(if ($rows.Count -eq 0) { 'Visible' } else { 'Collapsed' })
    $current = $Data.current
    $script:MainForm.FindName('CurrentEmail').Text = $(if ($current) { $current.email } else { '尚未检测到当前登录' })
    $script:MainForm.FindName('CurrentMode').Text = $(if (!$current) { '未登录' } elseif ($current.auth_method -eq 'gcp') { 'Cloud 按量计费' } else { 'Google 订阅模式' })
    $script:MainForm.FindName('CurrentBadge').Background = $(if ($current -and $current.auth_method -ne 'gcp') { '#F3EEFF' } else { '#EFF6FF' })
    $script:MainForm.FindName('CurrentMode').Foreground = $(if ($current -and $current.auth_method -ne 'gcp') { '#7C3AED' } else { '#2563EB' })
    $script:MainForm.FindName('CurrentProject').Text = $(if (!$current) { '添加 Google 账号，或保存官方客户端的当前登录。' } elseif ($current.auth_method -eq 'gcp') { "项目  $($current.project_id)    ·    地区  $($current.region)" } else { '使用此 Google 账号的可用订阅权益' })
    Update-SelectionState
}

function Refresh-AccountList { Set-AccountList (Get-AuthAccounts) }

function Run-UiOperation([scriptblock]$Operation) {
    $script:Busy = $true
    foreach ($button in $script:Buttons) { $button.IsEnabled = $false }
    $script:MainForm.Cursor = [Windows.Input.Cursors]::Wait
    Update-SelectionState
    $script:MainForm.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
    try { & $Operation; Refresh-AccountList }
    catch { Show-OperationError $_ }
    finally {
        $script:Busy = $false
        $script:MainForm.Cursor = $null
        foreach ($button in $script:Buttons) { $button.IsEnabled = $true }
        Update-SelectionState
    }
}

function Get-SelectedProfile {
    if (!$list.SelectedItem) { throw '请先在列表中选择一个已保存的账号配置。' }
    return $list.SelectedItem.Account
}

$list.Add_SelectionChanged({ Update-SelectionState })
$script:Buttons[7].Add_Click({ try { Edit-SelectedNote } catch { Show-OperationError $_ } })
$script:Buttons[6].Add_Click({ try { Remove-SelectedProfile } catch { Show-OperationError $_ } })
$script:Buttons[0].Add_Click({ Run-UiOperation { $account = Get-SelectedProfile; $null = Switch-AuthProfile $account.id } })
$script:Buttons[1].Add_Click({ Run-UiOperation { $null = Switch-AuthProfile '-' } })
$script:Buttons[2].Add_Click({ Run-UiOperation { $details = Request-AccountDetails; if ($details) { $null = Add-GoogleAccount $details } } })
$script:Buttons[3].Add_Click({ Run-UiOperation { $null = Invoke-AuthJson -Arguments @('add', '--target=cli') } })
$script:Buttons[4].Add_Click({ Run-UiOperation { } })
$script:Buttons[5].Add_Click({ Run-UiOperation {
    $account = Get-SelectedProfile
    $shell = New-Object -ComObject WScript.Shell
    $shortcutDir = Join-Path $script:DeploymentRoot '快捷切号'
    New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null
    $label = $(if ($account.alias) { $account.alias } else { $account.email }) -replace '[<>:"/\\|?*]', '_'
    $shortcut = $shell.CreateShortcut((Join-Path $shortcutDir ($label + ' - 切换 Antigravity.lnk')))
    $shortcut.TargetPath = [IO.Path]::GetFullPath((Join-Path $script:DeploymentRoot '..\launcher\AntigravityLauncher.exe'))
    $shortcut.Arguments = 'switch ' + (ConvertTo-NativeArgument $account.id)
    $shortcut.WorkingDirectory = $script:DeploymentRoot
    $shortcut.IconLocation = $script:Settings.desktopBinary + ',0'
    $shortcut.Save()
    Start-Process -FilePath explorer.exe -ArgumentList (ConvertTo-NativeArgument $shortcutDir)
} })

if ($SelfTest) {
    # Never read the real keyring or account registry during verification.
    function Get-AuthAccounts {
        $account = [PSCustomObject]@{ id='preview-cloud'; stored=$true; active=$true; email='writer@example.com'; alias='cloud-credit'; auth_method='gcp'; project_id='example-project'; region='global' }
        return [PSCustomObject]@{accounts=@($account); current=$account}
    }
    function Export-UiPreview($Window, [string]$File, [double]$Scale = 1) {
        $Window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
        $Window.UpdateLayout()
        $visual = $Window.Content
        $width = $visual.ActualWidth + $visual.Margin.Left + $visual.Margin.Right
        $height = $visual.ActualHeight + $visual.Margin.Top + $visual.Margin.Bottom
        $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int][Math]::Ceiling($width * $Scale), [int][Math]::Ceiling($height * $Scale), (96 * $Scale), (96 * $Scale), [Windows.Media.PixelFormats]::Pbgra32)
        $background = New-Object Windows.Media.DrawingVisual
        $drawing = $background.RenderOpen()
        $drawing.DrawRectangle($Window.Background, $null, (New-Object Windows.Rect(0, 0, $width, $height)))
        $drawing.Close()
        $bitmap.Render($background)
        $bitmap.Render($visual)
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create((Join-Path $PSScriptRoot $File))
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    function Show-TestWindow($Window) {
        $Window.ShowInTaskbar = $false
        $Window.WindowStartupLocation = 'Manual'
        $Window.Left = -12000; $Window.Top = -12000
        $Window.Show()
        $Window.UpdateLayout()
    }
    try {
        if ($list.Columns.Count -ne 5 -or $script:Buttons.Count -ne 8) { throw '界面组件检查失败。' }
        Show-TestWindow $script:MainForm
        $script:Buttons[4].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        Export-UiPreview $script:MainForm 'ui-check.png'
        Export-UiPreview $script:MainForm 'ui-check-150.png' 1.5
        Export-UiPreview $script:MainForm 'ui-check-200.png' 2
        $removePreview = New-RemoveProfileDialog (Get-SelectedProfile)
        try { Show-TestWindow $removePreview; Export-UiPreview $removePreview 'ui-check-RemoveProfile.png' 1.5 }
        finally { $removePreview.Close() }
        $hwnd = (New-Object Windows.Interop.WindowInteropHelper($script:MainForm)).Handle
        $awareness = [AccountManagerDpi]::GetAwarenessFromDpiAwarenessContext([AccountManagerDpi]::GetWindowDpiAwarenessContext($hwnd))
        if ($awareness -ne 2) { throw '窗口没有启用每显示器 DPI 感知。' }
        $dpi = [AccountManagerDpi]::GetDpiForWindow($hwnd)
        $renderDpi = [Windows.Media.VisualTreeHelper]::GetDpi($script:MainForm).PixelsPerInchX
        Set-AccountList ([PSCustomObject]@{accounts=@(); current=$null})
        if ($script:Buttons[0].IsEnabled -or $script:Buttons[5].IsEnabled -or $script:Buttons[6].IsEnabled -or $script:Buttons[7].IsEnabled) { throw '空列表仍可操作配置。' }
        Export-UiPreview $script:MainForm 'ui-check-empty.png'
        $demo = [PSCustomObject]@{ id='preview'; stored=$true; active=$true; email='writer@example.com'; alias='pro'; auth_method='consumer'; project_id=''; region='' }
        Set-AccountList ([PSCustomObject]@{accounts=@($demo); current=$demo})
        if ((Get-SelectedProfile).id -ne 'preview' -or !$script:Buttons[0].IsEnabled) { throw '配置选择状态检查失败。' }
        $sibling = (Get-AuthAccounts).current
        $noteData = [PSCustomObject]@{accounts=@($demo,$sibling); current=$demo}
        Set-ProfileNote $sibling.id '独立项目'
        Set-AccountList $noteData
        $expectedNote = ''
        foreach ($edit in @(@('写作账号',$true),@('未保存',$false),@('修改后的备注',$true),@('',$true),@('个人订阅',$true))) {
            $noteCheck = @{ Error=$null }
            $noteTimer = New-Object Windows.Threading.DispatcherTimer
            $noteTimer.Interval = [TimeSpan]::FromMilliseconds(100)
            $noteTimer.Add_Tick({
                $noteTimer.Stop()
                $testDialog = @($script:MainForm.OwnedWindows)[0]
                try {
                    $field = $testDialog.FindName('NoteInput')
                    if ($field.Text -cne $expectedNote) { throw '未显示已有备注。' }
                    $field.Text = $edit[0]
                    if ($edit[1]) { $testDialog.FindName('SaveNoteButton').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent))) }
                    else { $testDialog.DialogResult = $false }
                } catch { $noteCheck.Error = $_; $testDialog.Close() }
            })
            try { $noteTimer.Start(); $script:Buttons[7].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent))) }
            finally { $noteTimer.Stop() }
            if ($noteCheck.Error) { throw $noteCheck.Error }
            if ($edit[1]) { $expectedNote = $edit[0] }
            if ($list.SelectedItem.Note -cne $expectedNote) { throw '保存或取消备注后列表显示错误。' }
            Set-AccountList $noteData
            if ($list.SelectedItem.Note -cne $expectedNote -or $list.Items[1].Note -cne '独立项目') { throw '备注未持久保存或影响了同邮箱的其他配置。' }
        }
        Set-AccountList ([PSCustomObject]@{accounts=@($demo); current=$demo})
        $script:MainForm.Width = $script:MainForm.MinWidth
        $script:MainForm.Height = $script:MainForm.MinHeight
        Export-UiPreview $script:MainForm 'ui-check-compact.png'
        foreach ($name in @('AccountDetails', 'GoogleAuthorization')) {
            $preview = New-ManagerWindow $name
            try {
                if ($name -eq 'GoogleAuthorization') { $preview.FindName('TargetEmail').Text = 'writer@example.com' }
                Show-TestWindow $preview
                Export-UiPreview $preview ('ui-check-' + $name + '.png') 1.5
            } finally { $preview.Close() }
        }
        # Check the migrated form events without starting an OAuth process.
        $formCheck = @{ Error=$null }
        $formTimer = New-Object Windows.Threading.DispatcherTimer
        $formTimer.Interval = [TimeSpan]::FromMilliseconds(100)
        $formTimer.Add_Tick({
            $formTimer.Stop()
            $testDialog = @($script:MainForm.OwnedWindows)[0]
            try {
                $next = $testDialog.FindName('NextButton')
                $next.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                if ($testDialog.FindName('ValidationMessage').Visibility -ne 'Visible') { throw '空邮箱校验失效。' }
                $testDialog.FindName('CloudCheck').IsChecked = $true
                if (!$testDialog.FindName('ProjectInput').IsEnabled) { throw 'Cloud 项目输入状态失效。' }
                $testDialog.FindName('EmailInput').Text = 'preview@example.com'
                $testDialog.FindName('AliasInput').Text = 'ui-preview'
                $testDialog.FindName('ProjectInput').Text = 'preview-project'
                $next.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            } catch { $formCheck.Error = $_; $testDialog.Close() }
        })
        try { $formTimer.Start(); $testDetails = Request-AccountDetails }
        finally { $formTimer.Stop() }
        if ($formCheck.Error) { throw $formCheck.Error }
        if (!$testDetails.Cloud -or $testDetails.Email -ne 'preview@example.com' -or $testDetails.Project -ne 'preview-project') { throw '账号表单返回值检查失败。' }
        # Exercise the real delete button and confirmation UI with a fake backend.
        $script:RemoveTest = @{ Calls=0; LastId=$null; Error=$null; Confirm=$false; Rows=@($demo); Current=$demo }
        function Get-AuthAccounts { [PSCustomObject]@{accounts=$script:RemoveTest.Rows; current=$script:RemoveTest.Current} }
        function Remove-SavedProfile([string]$ProfileId) {
            $script:RemoveTest.Calls++
            $script:RemoveTest.LastId = $ProfileId
            $script:RemoveTest.Rows = @($script:RemoveTest.Rows | Where-Object { $_.id -ne $ProfileId })
        }
        $script:Busy = $true
        Update-SelectionState
        if ($script:Buttons[6].IsEnabled -or $script:Buttons[7].IsEnabled) { throw '操作进行中仍允许删除或编辑。' }
        $script:Busy = $false
        Update-SelectionState
        foreach ($confirm in @($false,$true)) {
            $script:RemoveTest.Confirm = $confirm
            $removeTimer = New-Object Windows.Threading.DispatcherTimer
            $removeTimer.Interval = [TimeSpan]::FromMilliseconds(100)
            $removeTimer.Add_Tick({
                $removeTimer.Stop()
                $testDialog = @($script:MainForm.OwnedWindows)[0]
                try {
                    if ($testDialog.FindName('ProfileEmail').Text -ne 'writer@example.com' -or !$testDialog.FindName('ProfileDetails').Text.Contains('pro')) { throw '删除确认未显示目标配置。' }
                    if (!$testDialog.FindName('CancelRemoveButton').IsDefault -or $testDialog.FindName('CurrentNotice').Visibility -ne 'Visible') { throw '删除确认的默认按钮或当前登录提示不正确。' }
                    if ($script:RemoveTest.Confirm) {
                        $testDialog.FindName('ConfirmRemoveButton').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                    } else { $testDialog.DialogResult = $false }
                } catch { $script:RemoveTest.Error = $_; $testDialog.Close() }
            })
            try {
                $removeTimer.Start()
                $script:Buttons[6].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            } finally { $removeTimer.Stop() }
            if ($script:RemoveTest.Error) { throw $script:RemoveTest.Error }
            if (!$confirm -and ($script:RemoveTest.Calls -ne 0 -or $list.Items.Count -ne 1)) { throw '取消删除仍改动了配置。' }
        }
        if ($script:RemoveTest.Calls -ne 1 -or $script:RemoveTest.LastId -ne 'preview' -or $list.Items.Count -ne 0 -or $script:Buttons[6].IsEnabled) { throw '确认删除或刷新列表失败。' }
        if ($script:MainForm.FindName('CurrentEmail').Text -ne 'writer@example.com') { throw '删除保存配置后当前登录信息丢失。' }
        if ((Get-ProfileNote $demo.id) -or (Get-ProfileNote $sibling.id) -cne '独立项目') { throw '删除配置时备注清理范围不正确。' }
        Write-Output "GUI_COMPONENTS_OK; PerMonitorDpiAware=True; WindowDpi=$dpi; RenderDpi=$renderDpi; PreviewScales=100,150,200; EmptyAndSelection=OK; DialogsAndValidation=OK; DeleteCancelAndConfirm=OK; ProfileNotes=OK"
    } finally {
        $script:MainForm.Close()
        if ([IO.Directory]::Exists($script:NotesDirectory)) {
            foreach ($testId in @('preview','preview-cloud')) { [IO.File]::Delete((Get-ProfileNotePath $testId)) }
            [IO.Directory]::Delete($script:NotesDirectory)
        }
    }
    return
}
$script:MainForm.Add_ContentRendered({ try { Refresh-AccountList } catch { Show-OperationError $_ } })
$script:WindowStatePath = Join-Path $PSScriptRoot 'ui-state.json'
if (Test-Path -LiteralPath $script:WindowStatePath -PathType Leaf) {
    $script:MainForm.WindowStartupLocation = 'Manual'
    $script:MainForm.Add_SourceInitialized({
        $handle = (New-Object Windows.Interop.WindowInteropHelper($script:MainForm)).Handle
        if (!(Restore-ManagerWindowState -Handle $handle -Path $script:WindowStatePath)) {
            $script:MainForm.WindowStartupLocation = 'CenterScreen'
        }
    })
}
$script:MainForm.Add_Closing({
    $handle = (New-Object Windows.Interop.WindowInteropHelper($script:MainForm)).Handle
    $null = Save-ManagerWindowState -Handle $handle -Path $script:WindowStatePath
})
[void]$script:MainForm.ShowDialog()
