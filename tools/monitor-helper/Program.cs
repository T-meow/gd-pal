using System.IO.Pipes;
using System.Security.Principal;
using System.Text.Json;
using GdPal.Monitoring;
using LibreHardwareMonitor.Hardware;
using Microsoft.Win32;

if (!OperatingSystem.IsWindows() || args.Length != 1 || !args[0].StartsWith("gdpal-sensors-", StringComparison.Ordinal)) return;
using var pipe = new NamedPipeClientStream(".", args[0], PipeDirection.InOut, PipeOptions.Asynchronous);
try { await pipe.ConnectAsync(12000); } catch { return; }
int sampling = 1;
// A suspended elevated reader retains its authorization; disconnect still exits immediately.
_ = Task.Run(async () => {
    try {
        using var input = new StreamReader(pipe, leaveOpen: true);
        while (await input.ReadLineAsync() is { } command) {
            if (command == "pause") Interlocked.Exchange(ref sampling, 0);
            else if (command == "resume") Interlocked.Exchange(ref sampling, 1);
            else if (command == "stop") break;
        }
    }
    catch { }
    Environment.Exit(0);
});
using var output = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };
bool elevated = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
bool driver = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\PawnIO") is { } key && DriverPresent(key);
await output.WriteLineAsync(JsonSerializer.Serialize(new SensorFrame { Elevated = elevated, DriverInstalled = driver, Connected = true }));
var computer = new Computer { IsCpuEnabled = true, IsGpuEnabled = true, IsMotherboardEnabled = true, IsControllerEnabled = true };
try
{
    computer.Open();
    var latest = new SensorFrame { Elevated = elevated, DriverInstalled = driver, Connected = true };
    while (pipe.IsConnected)
    {
        if (Volatile.Read(ref sampling) == 0) {
            // Heartbeat keeps the connection alive without claiming cached values are new samples.
            await output.WriteLineAsync(JsonSerializer.Serialize(latest with { Paused = true, Status = "温度、频率与风扇读取已暂停" }));
            await Task.Delay(1000);
            continue;
        }
        var readings = new List<SensorReading>();
        var errors = new List<string>();
        foreach (var hardware in computer.Hardware) Read(hardware, "board", hardware.Identifier.ToString(), hardware.Name, driver && elevated, readings, errors);
        var status = errors.Count > 0 ? "部分传感器读取失败：" + errors[0] :
            !driver ? "部分温度与风扇需要 PawnIO 驱动，当前显示可读取的传感器。" :
            !elevated ? "当前为普通权限；缺少读数时可启用高级读取。" : "传感器已连接";
        latest = new SensorFrame {
            Sensors = readings.ToArray(), Elevated = elevated, DriverInstalled = driver, Connected = true, Initialized = true, Status = status
        };
        await output.WriteLineAsync(JsonSerializer.Serialize(latest));
        await Task.Delay(2000);
    }
}
catch (Exception ex)
{
    try { await output.WriteLineAsync(JsonSerializer.Serialize(new SensorFrame { Status = "传感器读取失败：" + ex.Message, Elevated = elevated, DriverInstalled = driver, Connected = true })); }
    catch { }
}
finally { computer.Close(); }

static bool DriverPresent(RegistryKey key) { key.Dispose(); return true; }
static void Read(IHardware hardware, string kind, string deviceId, string deviceName, bool canReadCpu, List<SensorReading> readings, List<string> errors)
{
    if (hardware.HardwareType == HardwareType.Cpu) kind = "cpu";
    else if (hardware.HardwareType is HardwareType.GpuNvidia or HardwareType.GpuAmd or HardwareType.GpuIntel) kind = "gpu";
    if (kind is "cpu" or "gpu") { deviceId = hardware.Identifier.ToString(); deviceName = hardware.Name; }
    try
    {
        hardware.Update();
        foreach (var sensor in hardware.Sensors)
        {
            if (sensor.SensorType is not (SensorType.Temperature or SensorType.Fan or SensorType.Clock)) continue;
            if (sensor.SensorType == SensorType.Clock && kind is not ("cpu" or "gpu")) continue;
            double? value = sensor.Value is { } v && float.IsFinite(v) ? v : null;
            // LHM can expose a zero-valued AMD CPU sensor without usable driver access.
            // GPU temperatures and genuine 0 RPM fan readings remain valid.
            if (kind == "cpu" && sensor.SensorType == SensorType.Temperature && !canReadCpu && value == 0) value = null;
            string unit = sensor.SensorType switch { SensorType.Fan => "RPM", SensorType.Clock => "MHz", _ => "°C" };
            readings.Add(new SensorReading(sensor.Identifier.ToString(), sensor.Name, deviceId, deviceName,
                kind, sensor.SensorType.ToString(), unit, value));
        }
    }
    catch (Exception ex) { errors.Add(hardware.Name + "：" + ex.Message); }
    foreach (var child in hardware.SubHardware) Read(child, kind, deviceId, deviceName, canReadCpu, readings, errors);
}
