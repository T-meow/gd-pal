using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.Versioning;
using Godot;
using Environment = System.Environment;

namespace GdPal.Monitoring;

[GlobalClass]
public partial class PcMonitorService : Node
{
    [Signal] public delegate void SettingsChangedEventHandler();
    [Signal] public delegate void AlertRaisedEventHandler(string message);
    public event Action? Updated;
    public event Action? PreferencesChanged;
    private readonly HashSet<ulong> _subscribers = new();
    private readonly CancellationTokenSource _stop = new();
    private volatile MonitorSettings _settings = new();
    private volatile bool _sampling, _paused;
    private MonitorSnapshot? _pending;
    private SensorFrame? _pendingSensors;
    private int _sensorRestart;
    private string _settingsPath = "", _helper = "";
    private string[] _driverCandidates = [];
    private string _driverCache = "";
    private DriverResult? _pendingDriver;
    private sealed record DriverResult(string Message, bool Finished = false, bool Refresh = false);
    private DateTimeOffset _overheatSince, _lastAlert;
    public MonitorSnapshot Latest { get; private set; } = new();
    public SensorFrame Sensors { get; private set; } = new();
    public MonitorSettings Settings => _settings;
    public bool Supported => OperatingSystem.IsWindows();
    public bool Paused => _paused;
    public bool Stale => DateTimeOffset.UtcNow - Latest.Time > TimeSpan.FromSeconds(Settings.Interval * 3 + 1);
    public bool SensorStale => !_paused && (Sensors.Paused || DateTimeOffset.UtcNow - Sensors.Time > TimeSpan.FromSeconds(7));
    public List<MonitorSnapshot> History { get; } = new();
    public string AlertMessage { get; private set; } = "";
    public string PreferenceError { get; private set; } = "";
    public string DriverInstallStatus { get; private set; } = "";
    public bool InstallingDriver { get; private set; }

    public override void _Ready()
    {
        _settingsPath = ProjectSettings.GlobalizePath("user://pc_monitor_v1.json");
        try
        {
            if (OS.GetEnvironment("GD_PAL_TEST") != "1" && File.Exists(_settingsPath))
                _settings = JsonSerializer.Deserialize<MonitorSettings>(File.ReadAllText(_settingsPath)) ?? new();
            _settings = _settings with { Version = 1, Interval = new[] { 1, 2, 5 }.Contains(_settings.Interval) ? _settings.Interval : 1,
                DesktopPanels = _settings.DesktopPanels ?? new(), ExpandedPanels = _settings.ExpandedPanels ?? new(),
                MinimalTheme = _settings.MinimalTheme is "light" or "dark" ? _settings.MinimalTheme : "follow",
                MinimalOpacity = double.IsFinite(_settings.MinimalOpacity) ? Math.Clamp(_settings.MinimalOpacity, .05, .35) : .12,
                CpuLimit = double.IsFinite(_settings.CpuLimit) ? Math.Clamp(_settings.CpuLimit, 40, 110) : 90,
                GpuLimit = double.IsFinite(_settings.GpuLimit) ? Math.Clamp(_settings.GpuLimit, 40, 110) : 85,
                Disks = _settings.Disks is { } disks ? NormalizeDiskIds(disks) : null };
        }
        catch (Exception ex) { PreferenceError = "监控设置读取失败：" + ex.Message; }
        var besideAssembly = Path.GetDirectoryName(typeof(PcMonitorService).Assembly.Location) ?? AppContext.BaseDirectory;
        _helper = new[] { Path.Combine(besideAssembly, "monitor-helper", "GdPal.Sensors.exe"),
            Path.Combine(OS.GetExecutablePath().GetBaseDir(), "monitor-helper", "GdPal.Sensors.exe"),
            ProjectSettings.GlobalizePath("res://tools/monitor-helper/bin/Debug/net10.0/GdPal.Sensors.exe") }.FirstOrDefault(File.Exists) ?? "";
        _driverCandidates = [Path.Combine(OS.GetExecutablePath().GetBaseDir(), "components", "PawnIO", "PawnIO_setup.exe"),
            ProjectSettings.GlobalizePath("res://output/monitor-driver/PawnIO_setup.exe")];
        _driverCache = ProjectSettings.GlobalizePath("user://monitor-components/PawnIO_setup-" + SensorDriverInstaller.Version + ".exe");
#if WINDOWS_MONITOR
        if (OperatingSystem.IsWindows()) _ = Task.Run(SampleLoop);
#endif
    }

    public override void _Process(double delta)
    {
        _sampling = Supported && !_paused && (_subscribers.Count > 0 || Settings.Alerts);
        bool changed = false;
        var driver = Interlocked.Exchange(ref _pendingDriver, null);
        if (driver != null)
        {
            DriverInstallStatus = driver.Message;
            if (driver.Finished) InstallingDriver = false;
            if (driver.Refresh) RestartSensors(false);
            changed = true;
        }
        var sensors = Interlocked.Exchange(ref _pendingSensors, null);
        if (sensors != null) { Sensors = sensors; changed = true; }
        var sample = Interlocked.Exchange(ref _pending, null);
        if (sample != null)
        {
            Latest = sample; History.Add(sample);
            History.RemoveAll(s => sample.Time - s.Time > TimeSpan.FromSeconds(60));
            CheckAlert(); changed = true;
        }
        if (changed) Updated?.Invoke();
    }

    public void Subscribe(ulong id, bool visible) { if (visible) _subscribers.Add(id); else _subscribers.Remove(id); }
    public void SetPaused(bool value) { _paused = value; _overheatSince = default; Updated?.Invoke(); }
    public void SetDesktopVisibleFor(string profileId, bool value)
    {
        if (profileId.Length == 0 || IsDesktopVisibleFor(profileId) == value) return;
        var panels = new Dictionary<string, bool>(Settings.DesktopPanels) { [profileId] = value };
        Save(Settings with { DesktopPanels = panels });
    }
    public bool IsDesktopVisibleFor(string profileId) => profileId.Length > 0 && Settings.DesktopPanels.GetValueOrDefault(profileId, Settings.DesktopVisible);
    public void SetExpandedFor(string profileId, bool value)
    {
        if (profileId.Length == 0 || IsExpandedFor(profileId) == value) return;
        var panels = new Dictionary<string, bool>(Settings.ExpandedPanels) { [profileId] = value };
        Save(Settings with { ExpandedPanels = panels });
    }
    public bool IsExpandedFor(string profileId) => Settings.ExpandedPanels.GetValueOrDefault(profileId, Settings.Expanded);
    public string GetMinimalTheme() => Settings.MinimalTheme;
    public double GetMinimalOpacity() => Settings.MinimalOpacity;
    public void SetMinimalAppearance(string theme, double opacity) => Save(Settings with {
        MinimalTheme = theme is "light" or "dark" ? theme : "follow",
        MinimalOpacity = double.IsFinite(opacity) ? Math.Clamp(opacity, .05, .35) : .12 });
    public void SetInterval(int value) => Save(Settings with { Interval = value is 2 or 5 ? value : 1 });
    public void SelectGpu(string id) => Save(Settings with { Gpu = id, GpuTemperature = "" });
    public void SelectNetwork(string id) => Save(Settings with { Network = id });
    /// <summary>Pass null to show every disk automatically; pass ids (possibly none) for an explicit set.</summary>
    public void SelectDisks(IEnumerable<string>? ids) => Save(Settings with { Disks = ids == null ? null : NormalizeDiskIds(ids) });
    public bool DisksAutomatic => Settings.Disks == null;
    public MonitorDevice[] VisibleDisks(MonitorSnapshot? sample = null)
    {
        var disks = (sample ?? Latest).Disks;
        if (Settings.Disks is not { } ids) return disks;
        return disks.Where(d => ids.Contains(d.Id)).ToArray();
    }
    private static string[] NormalizeDiskIds(IEnumerable<string> ids) => ids
        .Where(id => !string.IsNullOrWhiteSpace(id)).Distinct().Take(32).ToArray();
    public void SelectSensor(string type, string id) => Save(type switch {
        "cpu_temp" => Settings with { CpuTemperature = id }, "gpu_temp" => Settings with { GpuTemperature = id },
        "cpu_fan" => Settings with { CpuFan = id }, _ => Settings });
    public void SetAlerts(bool enabled, double cpu, double gpu) => Save(Settings with { Alerts = enabled,
        CpuLimit = Math.Clamp(cpu, 40, 110), GpuLimit = Math.Clamp(gpu, 40, 110) });
    public void RestartSensors(bool elevated) { _paused = false; Interlocked.Exchange(ref _sensorRestart, elevated ? 2 : 1); Updated?.Invoke(); }
    public void InstallSensorDriver()
    {
        if (!OperatingSystem.IsWindows() || InstallingDriver) return;
        InstallingDriver = true;
        DriverInstallStatus = "正在准备官方 PawnIO 温度组件；未随包附带时会下载约 3.3 MB。";
        Updated?.Invoke();
        _ = Task.Run(async () => {
            try
            {
                string installer = await SensorDriverInstaller.PrepareAsync(_driverCandidates, _driverCache, _stop.Token);
                _stop.Token.ThrowIfCancellationRequested();
                Interlocked.Exchange(ref _pendingDriver, new("请在 Windows 授权窗口及官方安装器中完成安装。"));
                var start = new ProcessStartInfo(installer) { UseShellExecute = true, Verb = "runas", WorkingDirectory = Path.GetDirectoryName(installer)!, WindowStyle = ProcessWindowStyle.Normal };
                start.ArgumentList.Add("-install");
                using var process = Process.Start(start) ?? throw new IOException("无法打开官方驱动安装器。");
                await process.WaitForExitAsync(_stop.Token);
                string message = process.ExitCode switch {
                    0 => "安装器已完成。检测更新后，点击“启用高级读取”读取 CPU 温度。",
                    3010 => "驱动已安装，需要重启 Windows。重启后再启用高级读取。",
                    _ => "安装未完成（代码 " + process.ExitCode + "），可重试；基础占用率监控仍可使用。" };
                Interlocked.Exchange(ref _pendingDriver, new(message, true, process.ExitCode is 0 or 3010));
            }
            catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
            catch (OperationCanceledException) { Interlocked.Exchange(ref _pendingDriver, new("温度组件下载超时，请检查网络后重试，或通过“安装驱动说明”获取。", true)); }
            catch (Win32Exception ex) when (ex.NativeErrorCode == 1223) { Interlocked.Exchange(ref _pendingDriver, new("已取消管理员授权。需要温度时可再次安装组件。", true)); }
            catch (Exception ex) { Interlocked.Exchange(ref _pendingDriver, new("温度组件安装未完成：" + ex.Message, true)); }
        });
    }

    private void Save(MonitorSettings settings)
    {
        _settings = settings; _overheatSince = default;
        try
        {
            if (OS.GetEnvironment("GD_PAL_TEST") != "1") File.WriteAllText(_settingsPath, JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }));
            PreferenceError = "";
        }
        catch (Exception ex) { PreferenceError = "监控设置保存失败：" + ex.Message; }
        PreferencesChanged?.Invoke(); EmitSignal(SignalName.SettingsChanged); Updated?.Invoke();
    }

    public MonitorDevice? Gpu(MonitorSnapshot? sample = null) => Select((sample ?? Latest).Gpus, Settings.Gpu);
    public MonitorDevice? Network(MonitorSnapshot? sample = null)
    {
        var source = sample ?? Latest;
        string id = source.Networks.Any(d => d.Id == Settings.Network) ? Settings.Network : source.DefaultNetwork;
        return Select(source.Networks, id);
    }
    private static MonitorDevice? Select(MonitorDevice[] devices, string id) => devices.FirstOrDefault(d => d.Id == id) ?? devices.FirstOrDefault();
    public SensorReading? CpuTemperature => Temperature("cpu", Settings.CpuTemperature);
    public SensorReading? GpuTemperature => Temperature("gpu", Settings.GpuTemperature);
    private SensorReading? Temperature(string kind, string selected)
    {
        if (SensorStale) return null;
        if (selected.Length > 0 && Sensors.Sensors.FirstOrDefault(s => s.Id == selected && s.Kind == kind && s.Type == "Temperature") is { } bound) return bound;
        var candidates = Sensors.Sensors.Where(s => s.Kind == kind && s.Type == "Temperature" && s.Value.HasValue).ToArray();
        if (kind == "gpu")
        {
            string name = Gpu()?.Name ?? "";
            candidates = candidates.Where(s => Normalize(s.DeviceName) == Normalize(name)).ToArray();
            if (candidates.Select(s => s.DeviceId).Distinct().Count() != 1) return null;
            return candidates.FirstOrDefault(s => s.Name.Equals("GPU Core", StringComparison.OrdinalIgnoreCase));
        }
        return candidates.FirstOrDefault(s => s.Name.Contains("Tdie", StringComparison.OrdinalIgnoreCase))
            ?? candidates.FirstOrDefault(s => s.Name.Equals("CPU Package", StringComparison.OrdinalIgnoreCase))
            ?? candidates.FirstOrDefault(s => s.Name.Contains("Tctl", StringComparison.OrdinalIgnoreCase))
            ?? candidates.FirstOrDefault(s => s.Name.Equals("Core Average", StringComparison.OrdinalIgnoreCase))
            ?? candidates.OrderByDescending(s => s.Value).FirstOrDefault();
    }
    public string CpuTemperatureState => SensorStale ? "待更新" : !Sensors.Connected ? "未连接" : !Sensors.Initialized ? "读取中" : !Sensors.DriverInstalled ? "需驱动" : !Sensors.Elevated ? "需授权" : "未提供";
    public string CpuTemperatureHelp => SensorStale ? "温度数据已过期，请重新检测传感器。" : !Sensors.Connected || !Sensors.Initialized ? Sensors.Status : !Sensors.DriverInstalled
        ? "未安装 PawnIO，CPU 温度暂不可用。先安装官方驱动，再点击“启用高级读取”；Windows 会请求管理员授权。"
        : !Sensors.Elevated ? "CPU 温度暂不可读，可在传感器设置中启用高级读取。" : "CPU 未提供有效温度，可在传感器设置中更换来源。";
    public SensorReading? CpuFan => SensorStale ? null : Sensors.Sensors.FirstOrDefault(s => s.Type == "Fan" && s.Id == Settings.CpuFan)
        ?? Sensors.Sensors.FirstOrDefault(s => s.Type == "Fan" && s.Name.Contains("CPU", StringComparison.OrdinalIgnoreCase));
    public SensorReading? GpuFan
    {
        get
        {
            if (SensorStale) return null;
            var candidates = Sensors.Sensors.Where(s => s.Kind == "gpu" && Normalize(s.DeviceName) == Normalize(Gpu()?.Name ?? "")).ToArray();
            string? device = GpuTemperature?.DeviceId;
            if (device == null && candidates.Select(s => s.DeviceId).Distinct().Count() == 1) device = candidates.FirstOrDefault()?.DeviceId;
            return device == null ? null : Sensors.Sensors.FirstOrDefault(s => s.Type == "Fan" && s.DeviceId == device);
        }
    }
    public SensorReading[] OtherFans => SensorStale ? [] : Sensors.Sensors.Where(s => s.Type == "Fan" && s.Id != CpuFan?.Id && s.Id != GpuFan?.Id).ToArray();
    private static string Normalize(string name) => name.Replace("NVIDIA", "", StringComparison.OrdinalIgnoreCase)
        .Replace("AMD", "", StringComparison.OrdinalIgnoreCase).Replace("(R)", "", StringComparison.OrdinalIgnoreCase).Replace(" ", "").ToLowerInvariant();

    private void CheckAlert()
    {
        var cpu = CpuTemperature?.Value; var gpu = GpuTemperature?.Value;
        if (!Settings.Alerts || _paused || Stale || SensorStale || !(cpu >= Settings.CpuLimit || gpu >= Settings.GpuLimit))
        { _overheatSince = default; AlertMessage = ""; return; }
        var now = DateTimeOffset.UtcNow;
        if (_overheatSince == default) _overheatSince = now;
        if (now - _overheatSince < TimeSpan.FromSeconds(10) || now - _lastAlert < TimeSpan.FromMinutes(2)) return;
        _lastAlert = now;
        AlertMessage = cpu >= Settings.CpuLimit ? $"CPU 温度已持续超过 {Settings.CpuLimit:0} °C，当前 {cpu:0} °C。" : $"GPU 温度已持续超过 {Settings.GpuLimit:0} °C，当前 {gpu:0} °C。";
        EmitSignal(SignalName.AlertRaised, AlertMessage);
    }

#if WINDOWS_MONITOR
    [SupportedOSPlatform("windows")]
    private async Task SampleLoop()
    {
        using var metrics = new WindowsMetrics(); SensorClient? client = null;
        DateTimeOffset retry = default, lastActive = DateTimeOffset.UtcNow;
        try
        {
            while (!_stop.IsCancellationRequested)
            {
                if (!_sampling)
                {
                    if (DateTimeOffset.UtcNow - lastActive > TimeSpan.FromSeconds(5)) {
                        if (client is { Elevated: true, Completion.IsCompleted: false }) client.SetPaused(true);
                        else { client?.Dispose(); client = null; retry = default; }
                    }
                    await Task.Delay(250, _stop.Token); continue;
                }
                lastActive = DateTimeOffset.UtcNow;
                int restart = Interlocked.Exchange(ref _sensorRestart, 0);
                if (restart > 0) { client?.Dispose(); client = null; retry = default; }
                if (client is { Completion.IsCompleted: true }) { client.Dispose(); client = null; }
                if (client == null && DateTimeOffset.UtcNow >= retry)
                {
                    // Elevation is a one-shot request from the settings button; retries never prompt.
                    client = new SensorClient(_helper, restart == 2, f => Interlocked.Exchange(ref _pendingSensors, f));
                    retry = DateTimeOffset.UtcNow.AddSeconds(30);
                }
                client?.SetPaused(false);
                try { Interlocked.Exchange(ref _pending, metrics.Read(Settings.Interval)); }
                catch (Exception ex) { Interlocked.Exchange(ref _pending, new MonitorSnapshot { Error = "读取失败：" + ex.Message }); }
                await Task.Delay(Settings.Interval * 1000, _stop.Token);
            }
        }
        catch (OperationCanceledException) { }
        finally { client?.Dispose(); }
    }
#endif
    public override void _ExitTree() { _stop.Cancel(); _subscribers.Clear(); }
}
