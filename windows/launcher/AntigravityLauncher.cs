using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

// Windows GUI executable: child scripts never allocate a console or Terminal tab.
internal static class AntigravityLauncher
{
    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    private static string Quote(string value)
    {
        return "\"" + Regex.Replace(Regex.Replace(value, "(\\\\*)\"", "$1$1\\\""), "(\\\\+)$", "$1$1") + "\"";
    }

    [STAThread]
    private static int Main(string[] args)
    {
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        try
        {
            string root = Directory.GetParent(AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\')).FullName;
            string mode = args.Length == 0 ? "manager" : args[0];
            string script;
            string title = "Antigravity";
            string extra = "";
            bool report = false;
            switch (mode)
            {
                case "manager": script = @"agy-auth\Account-Manager.ps1"; break;
                case "switch":
                    if (args.Length != 2) throw new ArgumentException("请选择要切换的配置。");
                    script = @"agy-auth\Switch-Account.ps1";
                    extra = " -Profile " + Quote(args[1]);
                    break;
                case "update-auth": script = @"agy-auth\Update-AgyAuth.ps1"; title = "更新账号管理工具"; report = true; break;
                case "update-theme": script = @"antigravity-cn\Update-Antigravity-ThemePatch.ps1"; title = "更新 Antigravity 汉化"; report = true; break;
                case "check-theme": script = @"antigravity-cn\Check-ThemePatch.ps1"; title = "检查汉化状态"; report = true; break;
                case "self-test": script = @"launcher\Verify-QuietLaunch.ps1"; break;
                case "open-config":
                    Process.Start("explorer.exe", Quote(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".gemini\antigravity\theme-patch\user")));
                    return 0;
                default: throw new ArgumentException("无法识别的一键操作。");
            }
            if (mode != "switch")
            {
                for (int i = 1; i < args.Length; i++)
                {
                    if ((mode == "update-auth" || mode == "update-theme") && args[i].Equals("-CheckOnly", StringComparison.OrdinalIgnoreCase)) extra += " -CheckOnly";
                    else if (mode == "update-theme" && args[i].Equals("-Reinstall", StringComparison.OrdinalIgnoreCase)) extra += " -Reinstall";
                    else throw new ArgumentException("不支持的启动参数：" + args[i]);
                }
            }
            string fullPath = Path.Combine(root, script);
            if (!File.Exists(fullPath)) throw new FileNotFoundException("找不到所需脚本。", fullPath);
            var info = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File " + Quote(fullPath) + extra,
                WorkingDirectory = Path.GetDirectoryName(fullPath),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            if (report)
            {
                using (var window = new OperationWindow(info, title))
                {
                    Application.Run(window);
                    return window.ExitCode;
                }
            }
            // Consume output without retaining account metadata or auth errors.
            int exitCode = RunCapturedProcess(info, null).GetAwaiter().GetResult();
            if (exitCode != 0 && mode != "switch")
                MessageBox.Show("操作未能完成。请检查本地脚本与安装路径；需要诊断时可在 PowerShell 中手动运行对应脚本。", title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return exitCode;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Antigravity 启动失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
    }

    internal static async Task<int> RunCapturedProcess(ProcessStartInfo info, Action<string> onLine)
    {
        using (var process = new Process { StartInfo = info })
        {
            var outputEnded = new TaskCompletionSource<bool>();
            var errorEnded = new TaskCompletionSource<bool>();
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs data)
            {
                if (data.Data == null) outputEnded.TrySetResult(true);
                else if (onLine != null) onLine(data.Data);
            };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs data)
            {
                if (data.Data == null) errorEnded.TrySetResult(true);
                else if (onLine != null) onLine(data.Data);
            };
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            // The parameterless WaitForExit also waits for redirected-pipe EOF.
            // An installed daemon can inherit those handles and keep them open
            // indefinitely, even after the update script has exited successfully.
            await Task.Run(delegate { while (!process.WaitForExit(250)) { } }).ConfigureAwait(false);
            int exitCode = process.ExitCode;
            await Task.WhenAny(Task.WhenAll(outputEnded.Task, errorEnded.Task), Task.Delay(1000)).ConfigureAwait(false);
            process.CancelOutputRead();
            process.CancelErrorRead();
            return exitCode;
        }
    }

    internal sealed class OperationWindow : Form
    {
        private readonly ProcessStartInfo info;
        private readonly Label status;
        private readonly ProgressBar progress;
        private readonly TextBox output;
        private readonly Button close;
        private bool running = true;
        internal int ExitCode = 1;

        internal OperationWindow(ProcessStartInfo processInfo, string title)
        {
            info = processInfo;
            Text = title;
            Font = new Font("Microsoft YaHei UI", 10);
            AutoScaleDimensions = new SizeF(96, 96);
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(740, 460);
            MinimumSize = new Size(600, 360);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(245, 247, 251);
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(20), ColumnCount = 1, RowCount = 4 };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
            status = new Label { Text = "正在执行，请稍候…", Dock = DockStyle.Fill, AutoSize = false };
            progress = new ProgressBar { Dock = DockStyle.Fill, Style = ProgressBarStyle.Marquee, Margin = new Padding(3, 0, 3, 12) };
            output = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill, BackColor = Color.White };
            close = new Button { Text = "执行中…", Enabled = false, Width = 110, Height = 36, Anchor = AnchorStyles.Right | AnchorStyles.Bottom };
            close.Click += delegate { Close(); };
            layout.Controls.Add(status, 0, 0);
            layout.Controls.Add(progress, 0, 1);
            layout.Controls.Add(output, 0, 2);
            layout.Controls.Add(close, 0, 3);
            Controls.Add(layout);
            Shown += RunOperation;
            FormClosing += delegate(object sender, FormClosingEventArgs e)
            {
                if (running) { e.Cancel = true; status.Text = "操作尚未完成，可最小化此窗口等待。"; }
            };
        }

        private void Append(string line)
        {
            if (line == null || IsDisposed || Disposing) return;
            try
            {
                BeginInvoke(new Action(delegate { if (!IsDisposed && !Disposing) output.AppendText(line + Environment.NewLine); }));
            }
            catch (InvalidOperationException) { /* The result window was closed as output arrived. */ }
        }

        private async void RunOperation(object sender, EventArgs e)
        {
            try
            {
                ExitCode = await RunCapturedProcess(info, Append);
                status.Text = ExitCode == 0 ? "已完成，可以关闭此窗口。" : "操作未完成，请查看下方原因。";
            }
            catch (Exception error) { output.AppendText(error.Message); status.Text = "操作未完成。"; }
            finally
            {
                running = false;
                progress.Style = ProgressBarStyle.Continuous;
                progress.Value = 100;
                close.Enabled = true;
                close.Text = "关闭";
                close.Focus();
            }
        }
    }
}
