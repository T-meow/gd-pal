#if WINDOWS_MONITOR
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Runtime.Versioning;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace GdPal.Monitoring;

[SupportedOSPlatform("windows")]
internal sealed class SensorClient : IDisposable
{
    private readonly CancellationTokenSource _stop = new();
    private NamedPipeServerStream? _pipe;
    private Process? _process;
    private volatile bool _paused, _elevated;
    public Task Completion { get; }
    public bool Elevated => _elevated;
    public void SetPaused(bool value) => _paused = value;
    public SensorClient(string executable, bool elevated, Action<SensorFrame> receive) => Completion = Task.Run(() => Run(executable, elevated, receive));

    private async Task Run(string executable, bool elevated, Action<SensorFrame> receive)
    {
        Task? control = null;
        try
        {
            if (!File.Exists(executable)) throw new FileNotFoundException("未找到传感器程序，请重新构建项目。", executable);
            string name = "gdpal-sensors-" + Guid.NewGuid().ToString("N");
            // An explicit user SID ACL allows the same user's elevated helper too.
            var security = new PipeSecurity();
            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User!, PipeAccessRights.FullControl, AccessControlType.Allow));
            _pipe = NamedPipeServerStreamAcl.Create(name, PipeDirection.InOut, 1, PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous, 0, 0, security);
            var start = new ProcessStartInfo(executable) { UseShellExecute = elevated, CreateNoWindow = !elevated,
                WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = Path.GetDirectoryName(executable)! };
            start.ArgumentList.Add(name);
            if (elevated) start.Verb = "runas";
            _stop.Token.ThrowIfCancellationRequested();
            _process = Process.Start(start) ?? throw new IOException("无法启动传感器程序。");
            await _pipe.WaitForConnectionAsync(_stop.Token).WaitAsync(TimeSpan.FromSeconds(30), _stop.Token);
            control = SendState(_pipe);
            using var reader = new StreamReader(_pipe, leaveOpen: true);
            while (!_stop.IsCancellationRequested)
            {
                var json = await reader.ReadLineAsync(_stop.Token).AsTask().WaitAsync(TimeSpan.FromSeconds(20), _stop.Token);
                if (json == null) throw new IOException("传感器程序已退出。");
                if (json.Length > 2_000_000) throw new IOException("传感器响应过大。");
                var frame = JsonSerializer.Deserialize<SensorFrame>(json);
                if (frame != null && !_stop.IsCancellationRequested) { _elevated = frame.Elevated; receive(frame); }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            if (!_stop.IsCancellationRequested) receive(new SensorFrame { Status = "传感器暂不可用：" + ex.Message });
        }
        finally
        {
            // Closing the pipe asks the helper's watchdog to exit, including elevated workers.
            _pipe?.Dispose();
            _stop.Cancel();
            if (control != null) { try { await control; } catch { } }
            try { if (_process is { HasExited: false }) _process.Kill(); } catch { }
            _process?.Dispose();
        }
    }
    private async Task SendState(Stream stream)
    {
        using var writer = new StreamWriter(stream, leaveOpen: true) { AutoFlush = true };
        bool? sent = null;
        try {
            while (!_stop.IsCancellationRequested) {
                bool paused = _paused;
                if (sent != paused) { await writer.WriteLineAsync(paused ? "pause" : "resume"); sent = paused; }
                await Task.Delay(250, _stop.Token);
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { _stop.Cancel(); }
        catch (ObjectDisposedException) { }
    }
    public void Dispose() { _stop.Cancel(); _pipe?.Dispose(); }
}
#endif
