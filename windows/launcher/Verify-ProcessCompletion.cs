using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

// Isolated regression fixture: no update, credentials, or production daemon.
internal static class VerifyProcessCompletion
{
    private static ProcessStartInfo Fixture(string arguments, bool redirect)
    {
        return new ProcessStartInfo {
            FileName = typeof(VerifyProcessCompletion).Assembly.Location,
            Arguments = arguments,
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = redirect, RedirectStandardError = redirect
        };
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--holder") { Thread.Sleep(12000); return 0; }
        if (args.Length > 0 && args[0] == "--parent")
        {
            using (var child = Process.Start(Fixture("--holder", false)))
                Console.WriteLine("HOLDER_PID=" + child.Id);
            Console.WriteLine("FINAL_OUTPUT");
            Console.Error.WriteLine("FINAL_ERROR");
            return int.Parse(args[1]);
        }
        string resultPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "completion-verification.txt");
        try
        {
            foreach (int expectedExit in new[] { 0, 7 })
            {
                var lines = new ConcurrentQueue<string>();
                Task<int> task = AntigravityLauncher.RunCapturedProcess(Fixture("--parent " + expectedExit, true), lines.Enqueue);
                try
                {
                    if (!task.Wait(6000)) throw new Exception("Completion still waits for the inherited pipe.");
                    if (task.Result != expectedExit) throw new Exception("Exit status was not preserved.");
                    if (!lines.Contains("FINAL_OUTPUT") || !lines.Contains("FINAL_ERROR")) throw new Exception("Final output was lost.");
                    int holderId = int.Parse(lines.Single(line => line.StartsWith("HOLDER_PID=")).Substring(11));
                    using (var holder = Process.GetProcessById(holderId))
                        if (holder.HasExited) throw new Exception("Fixture did not leave a background process running.");
                }
                finally
                {
                    foreach (string line in lines.Where(line => line.StartsWith("HOLDER_PID=")))
                    {
                        try
                        {
                            using (var holder = Process.GetProcessById(int.Parse(line.Substring(11))))
                                if (!holder.HasExited && holder.MainModule.FileName == typeof(VerifyProcessCompletion).Assembly.Location) holder.Kill();
                        }
                        catch (ArgumentException) { }
                    }
                }
            }
            // Confirm this fixture reproduces the original parameterless wait bug.
            using (var parent = Process.Start(Fixture("--parent 0", true)))
            {
                var holderPid = new TaskCompletionSource<int>();
                parent.OutputDataReceived += delegate(object sender, DataReceivedEventArgs data) {
                    if (data.Data != null && data.Data.StartsWith("HOLDER_PID=")) holderPid.TrySetResult(int.Parse(data.Data.Substring(11)));
                };
                parent.BeginOutputReadLine(); parent.BeginErrorReadLine();
                if (!parent.WaitForExit(3000)) throw new Exception("Fixture parent did not exit.");
                if (!holderPid.Task.Wait(3000)) throw new Exception("Fixture child PID was not received.");
                int holderId = holderPid.Task.Result;
                Task oldWait = Task.Run(delegate { parent.WaitForExit(); });
                bool reproduced = !oldWait.Wait(500);
                using (var holder = Process.GetProcessById(holderId)) holder.Kill();
                if (!oldWait.Wait(3000)) throw new Exception("Fixture cleanup failed.");
                if (!reproduced) throw new Exception("Fixture did not reproduce the original bug.");
            }
            // Exercise the actual result form, including its Close button state.
            foreach (int expectedExit in new[] { 0, 7 })
            {
                using (var window = new AntigravityLauncher.OperationWindow(Fixture("--parent " + expectedExit, true), "Completion regression"))
                using (var timer = new System.Windows.Forms.Timer())
                {
                    window.ShowInTaskbar = false;
                    window.Opacity = 0;
                    var started = Stopwatch.StartNew();
                    bool completed = false;
                    timer.Interval = 100;
                    timer.Tick += delegate {
                        var panel = (TableLayoutPanel)window.Controls[0];
                        var button = (Button)panel.GetControlFromPosition(0, 3);
                        if (button.Enabled)
                        {
                            var status = (Label)panel.GetControlFromPosition(0, 0);
                            completed = window.ExitCode == expectedExit && status.Text.StartsWith(expectedExit == 0 ? "已完成" : "操作未完成");
                            string log = ((TextBox)panel.GetControlFromPosition(0, 2)).Text;
                            string pidLine = log.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).Single(line => line.StartsWith("HOLDER_PID="));
                            using (var holder = Process.GetProcessById(int.Parse(pidLine.Substring(11)))) holder.Kill();
                            button.PerformClick();
                        }
                        else if (started.ElapsedMilliseconds > 6000) throw new Exception("Result form is still waiting.");
                    };
                    timer.Start();
                    Application.Run(window);
                    timer.Stop();
                    if (!completed) throw new Exception("Result form did not show the correct completion status.");
                }
            }
            File.WriteAllText(resultPath, "PASS: reproduced old wait; fixed completion with a live inherited-pipe child; exit codes 0/7; final stdout/stderr preserved; actual result form status and Close button passed; fixture children stopped.");
            return 0;
        }
        catch (Exception error) { File.WriteAllText(resultPath, "FAIL: " + error); return 1; }
    }
}
