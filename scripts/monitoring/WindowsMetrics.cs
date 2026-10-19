#if WINDOWS_MONITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.RegularExpressions;
using static Vanara.PInvoke.Pdh;

namespace GdPal.Monitoring;

/// <summary>One background sampler; no Godot objects and no privileged hardware access.</summary>
[SupportedOSPlatform("windows")]
internal sealed class WindowsMetrics : IDisposable
{
    private SafePDH_HQUERY? _query;
    private readonly Dictionary<string, SafePDH_HCOUNTER> _counters = new();
    private readonly Dictionary<string, (long Rx, long Tx, long Tick)> _network = new();
    private NetworkInterface[] _interfaces = [];
    private List<Adapter> _adapters = [];
    private ulong _idle, _kernel, _user;
    private long _last, _discovered;
    private static readonly Regex GpuKey = new(@"luid_0x([0-9a-f]+)_0x([0-9a-f]+)_phys_(\d+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex EngineKey = new(@"_eng_(\d+)_", RegexOptions.Compiled);
    private static readonly Dictionary<string, string> Paths = new()
    {
        ["cpu"] = @"\Processor Information(_Total)\% Processor Time",
        ["gpu"] = @"\GPU Engine(*)\Utilization Percentage",
        ["vram"] = @"\GPU Adapter Memory(*)\Dedicated Usage",
        ["shared"] = @"\GPU Adapter Memory(*)\Shared Usage",
        ["disk"] = @"\PhysicalDisk(*)\% Idle Time",
        ["read"] = @"\PhysicalDisk(*)\Disk Read Bytes/sec",
        ["write"] = @"\PhysicalDisk(*)\Disk Write Bytes/sec"
    };

    public MonitorSnapshot Read(int interval)
    {
        long now = Stopwatch.GetTimestamp();
        double elapsed = _last == 0 ? 0 : (now - _last) / (double)Stopwatch.Frequency;
        bool baseline = elapsed <= 0 || elapsed > Math.Max(10, interval * 3);
        if (baseline) { ResetQuery(); _network.Clear(); }
        if (_discovered == 0 || (now - _discovered) / (double)Stopwatch.Frequency >= 10)
        {
            try { _interfaces = NetworkInterface.GetAllNetworkInterfaces(); } catch { _interfaces = []; }
            try { _adapters = FindAdapters(); } catch { _adapters = []; }
            _discovered = now;
            AddCounters();
        }
        if (_query == null) AddCounters();
        bool collected = _query != null && (uint)PdhCollectQueryData(_query) == 0;
        double? cpu = null;
        if (GetSystemTimes(out ulong idle, out ulong kernel, out ulong user))
        {
            if (!baseline && kernel >= _kernel && user >= _user && idle >= _idle)
            {
                ulong total = kernel - _kernel + user - _user;
                if (total > 0) cpu = Math.Clamp(100.0 * (1 - (idle - _idle) / (double)total), 0, 100);
            }
            (_idle, _kernel, _user) = (idle, kernel, user);
        }
        if (GetActiveProcessorCount(0xffff) > 64) cpu = !baseline && collected ? Values("cpu").Values.Cast<double?>().FirstOrDefault() : null;
        var mem = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        bool memoryOk = GlobalMemoryStatusEx(ref mem);
        var engines = collected && !baseline ? Values("gpu") : new();
        var engineTotals = new Dictionary<string, Dictionary<string, double>>();
        foreach (var (instance, value) in engines)
        {
            var gpu = ParseGpu(instance); var engine = EngineKey.Match(instance);
            if (gpu.Length == 0 || !engine.Success) continue;
            if (!engineTotals.TryGetValue(gpu, out var totals)) engineTotals[gpu] = totals = new();
            string key = engine.Groups[1].Value;
            totals[key] = totals.GetValueOrDefault(key) + value;
        }
        var vram = collected ? Values("vram") : new();
        var shared = collected ? Values("shared") : new();
        double? MemoryFor(Dictionary<string, double> values, string id) => values
            .Where(kv => ParseGpu(kv.Key) == id).Select(kv => (double?)kv.Value).FirstOrDefault();
        var gpus = _adapters.Select(a => new MonitorDevice(a.Id, a.Name,
            engineTotals.TryGetValue(a.Id, out var totals) && totals.Count > 0 ? Math.Clamp(totals.Values.Max(), 0, 100) : null,
            MemoryFor(vram, a.Id), a.Vram > 0 ? a.Vram : null, Shared: MemoryFor(shared, a.Id))).ToArray();
        var idleDisks = collected && !baseline ? Values("disk") : new();
        var reads = collected && !baseline ? Values("read") : new();
        var writes = collected && !baseline ? Values("write") : new();
        var disks = idleDisks.Keys.Concat(reads.Keys).Concat(writes.Keys).Distinct().Where(id => id != "_Total")
            .OrderBy(id => int.TryParse(id.Split(' ')[0], out var n) ? n : int.MaxValue)
            .Select(id => new MonitorDevice(id, DiskName(id),
                idleDisks.TryGetValue(id, out var idleDisk) ? Math.Clamp(100 - idleDisk, 0, 100) : null,
                Receive: reads.TryGetValue(id, out var r) ? r : null, Send: writes.TryGetValue(id, out var w) ? w : null)).ToArray();
        var networks = new List<MonitorDevice>(); string preferred = "";
        GetBestInterface(0x08080808, out uint bestIndex);
        foreach (var nic in _interfaces)
        {
            try
            {
                if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                var stats = nic.GetIPStatistics(); double? rx = null, tx = null;
                if (_network.TryGetValue(nic.Id, out var previous))
                {
                    double seconds = (now - previous.Tick) / (double)Stopwatch.Frequency;
                    if (seconds > 0 && stats.BytesReceived >= previous.Rx && stats.BytesSent >= previous.Tx)
                    { rx = (stats.BytesReceived - previous.Rx) / seconds; tx = (stats.BytesSent - previous.Tx) / seconds; }
                }
                _network[nic.Id] = (stats.BytesReceived, stats.BytesSent, now);
                networks.Add(new(nic.Id, nic.Name, Receive: rx, Send: tx, Total: nic.Speed > 0 ? nic.Speed : null));
                var ip = nic.GetIPProperties();
                if (nic.Supports(NetworkInterfaceComponent.IPv4) && ip.GetIPv4Properties().Index == bestIndex) preferred = nic.Id;
                else if (preferred.Length == 0 && ip.GatewayAddresses.Count > 0) preferred = nic.Id;
            }
            catch (NetworkInformationException) { _network.Remove(nic.Id); }
            catch (InvalidOperationException) { _network.Remove(nic.Id); }
        }
        _last = now;
        return new MonitorSnapshot { Cpu = cpu, MemoryUsed = memoryOk ? mem.TotalPhysical - mem.AvailablePhysical : null,
            MemoryTotal = memoryOk ? mem.TotalPhysical : null, Gpus = gpus, Networks = networks.ToArray(), Disks = disks,
            DefaultNetwork = preferred, Error = collected ? "" : "性能计数器暂不可用，基础内存与网速仍可读取。" };
    }

    private void AddCounters()
    {
        try
        {
            if (_query == null && (uint)PdhOpenQuery(null, IntPtr.Zero, out _query) != 0) { _query?.Dispose(); _query = null; return; }
            foreach (var (id, path) in Paths)
            {
                if (_counters.ContainsKey(id)) continue;
                if ((uint)PdhAddEnglishCounter(_query!, path, IntPtr.Zero, out var counter) == 0) _counters[id] = counter;
                else counter?.Dispose();
            }
        }
        catch { ResetQuery(); }
    }

    private Dictionary<string, double> Values(string id)
    {
        var result = new Dictionary<string, double>();
        if (!_counters.TryGetValue(id, out var counter)) return result;
        uint bytes = 0, count = 0;
        PdhGetFormattedCounterArray(counter, PDH_FMT.PDH_FMT_DOUBLE | PDH_FMT.PDH_FMT_NOCAP100, ref bytes, out count, IntPtr.Zero);
        for (int attempt = 0; attempt < 2 && bytes > 0 && bytes < 32 * 1024 * 1024; attempt++)
        {
            IntPtr buffer = Marshal.AllocHGlobal((int)bytes);
            try
            {
                uint status = (uint)PdhGetFormattedCounterArray(counter, PDH_FMT.PDH_FMT_DOUBLE | PDH_FMT.PDH_FMT_NOCAP100, ref bytes, out count, buffer);
                if (status == 0x800007d2) continue; // Dynamic GPU instances may resize the buffer between calls.
                if (status != 0) return result;
                int size = Marshal.SizeOf<PDH_FMT_COUNTERVALUE_ITEM>();
                for (int i = 0; i < count; i++)
                {
                    var item = Marshal.PtrToStructure<PDH_FMT_COUNTERVALUE_ITEM>(buffer + i * size);
                    if ((uint)item.FmtValue.CStatus <= 1 && double.IsFinite(item.FmtValue.doubleValue))
                        result[item.szName] = item.FmtValue.doubleValue;
                }
                return result;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        return result;
    }

    private static string DiskName(string id)
    {
        int space = id.IndexOf(' ');
        return space > 0 ? "磁盘 " + id[..space] + " · " + id[(space + 1)..] : "磁盘 " + id;
    }
    private static string ParseGpu(string instance)
    {
        var m = GpuKey.Match(instance);
        return m.Success ? $"{Convert.ToUInt32(m.Groups[1].Value, 16):x8}_{Convert.ToUInt32(m.Groups[2].Value, 16):x8}_{m.Groups[3].Value}" : "";
    }
    private void ResetQuery() { foreach (var c in _counters.Values) c.Dispose(); _counters.Clear(); _query?.Dispose(); _query = null; }
    public void Dispose() => ResetQuery();

    [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetSystemTimes(out ulong idle, out ulong kernel, out ulong user);
    [DllImport("kernel32.dll")] private static extern uint GetActiveProcessorCount(ushort group);
    [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    [DllImport("iphlpapi.dll")] private static extern uint GetBestInterface(uint destination, out uint index);
    [StructLayout(LayoutKind.Sequential)] private struct MemoryStatus
    { public uint Length, Load; public ulong TotalPhysical, AvailablePhysical, TotalPage, AvailablePage, TotalVirtual, AvailableVirtual, Extended; }

    private sealed record Adapter(string Id, string Name, ulong Vram);
    private static List<Adapter> FindAdapters()
    {
        var adapters = new List<Adapter>(); var iid = typeof(IDXGIFactory1).GUID;
        if (CreateDXGIFactory1(ref iid, out var factory) < 0) return adapters;
        try
        {
            for (uint i = 0; factory.EnumAdapters1(i, out var adapter) == 0; i++)
            {
                try
                {
                    if (adapter.GetDesc1(out var d) < 0 || (d.Flags & 2) != 0) continue;
                    adapters.Add(new($"{d.High:x8}_{d.Low:x8}_0", d.Description.TrimEnd('\0'), (ulong)d.DedicatedVideoMemory));
                }
                finally { Marshal.ReleaseComObject(adapter); }
            }
        }
        finally { Marshal.ReleaseComObject(factory); }
        return adapters;
    }
    [DllImport("dxgi.dll")] private static extern int CreateDXGIFactory1(ref Guid iid, out IDXGIFactory1 factory);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct AdapterDesc
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint Vendor, Device, Subsystem, Revision;
        public UIntPtr DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
        public uint Low, High, Flags;
    }
    // Keep all inherited COM slots in their native order, even when unused.
    [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDXGIFactory1
    {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        void EnumAdapters(); void MakeWindowAssociation(); void GetWindowAssociation(); void CreateSwapChain(); void CreateSoftwareAdapter();
        [PreserveSig] int EnumAdapters1(uint index, out IDXGIAdapter1 adapter);
    }
    [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDXGIAdapter1
    {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        void EnumOutputs(); void GetDesc(); void CheckInterfaceSupport();
        [PreserveSig] int GetDesc1(out AdapterDesc desc);
    }
}
#endif
