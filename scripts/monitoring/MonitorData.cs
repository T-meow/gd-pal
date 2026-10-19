using System;
using System.Collections.Generic;

namespace GdPal.Monitoring;

public sealed record MonitorDevice(string Id, string Name, double? Usage = null, double? Used = null,
    double? Total = null, double? Receive = null, double? Send = null, double? Shared = null);

public sealed record SensorReading(string Id, string Name, string DeviceId, string DeviceName,
    string Kind, string Type, string Unit, double? Value);

public sealed record SensorFrame
{
    public DateTimeOffset Time { get; init; } = DateTimeOffset.UtcNow;
    public SensorReading[] Sensors { get; init; } = [];
    public string Status { get; init; } = "正在读取传感器…";
    public bool Elevated { get; init; }
    public bool DriverInstalled { get; init; }
    public bool Connected { get; init; }
    public bool Initialized { get; init; }
    public bool Paused { get; init; }
}

public sealed record MonitorSnapshot
{
    public DateTimeOffset Time { get; init; } = DateTimeOffset.UtcNow;
    public double? Cpu { get; init; }
    public double? MemoryUsed { get; init; }
    public double? MemoryTotal { get; init; }
    public double? MemoryPercent => MemoryTotal > 0 ? MemoryUsed / MemoryTotal * 100 : null;
    public MonitorDevice[] Gpus { get; init; } = [];
    public MonitorDevice[] Networks { get; init; } = [];
    public MonitorDevice[] Disks { get; init; } = [];
    public string DefaultNetwork { get; init; } = "";
    public string Error { get; init; } = "";
}

public sealed record MonitorSettings
{
    public int Version { get; init; } = 1;
    public int Interval { get; init; } = 1;
    public bool DesktopVisible { get; init; } = true;
    public bool Expanded { get; init; }
    public Dictionary<string, bool> DesktopPanels { get; init; } = new();
    public Dictionary<string, bool> ExpandedPanels { get; init; } = new();
    public string MinimalTheme { get; init; } = "follow";
    public double MinimalOpacity { get; init; } = .12;
    public string Gpu { get; init; } = "";
    public string Network { get; init; } = "";
    /// <summary>null means automatic (every disk); an empty array means the user hid all disks.</summary>
    public string[]? Disks { get; init; }
    public string CpuTemperature { get; init; } = "";
    public string GpuTemperature { get; init; } = "";
    public string CpuFan { get; init; } = "";
    public bool Alerts { get; init; }
    public double CpuLimit { get; init; } = 90;
    public double GpuLimit { get; init; } = 85;
}
