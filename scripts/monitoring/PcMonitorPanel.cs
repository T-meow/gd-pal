using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace GdPal.Monitoring;

[GlobalClass]
public partial class PcMonitorPanel : MarginContainer
{
    [Signal] public delegate void HallRequestedEventHandler();
    [Signal] public delegate void DismissRequestedEventHandler();
    [Signal] public delegate void MinimalModeRequestedEventHandler();
    private PcMonitorService? _service;
    private int _mode;
    private string _profileId = "";
    private bool _buildQueued;
    private double _clock;
    private bool _settingsOpen, _visibleSubscribed;
    private readonly Dictionary<string, Label> _labels = new();
    private readonly Dictionary<string, OptionButton> _choices = new();
    private readonly Dictionary<string, string[]> _choiceIds = new();
    private readonly List<MonitorChart> _charts = new();
    private readonly Dictionary<string, (Label Busy, Label Io, ProgressBar Bar)> _diskRows = new();
    private GridContainer? _diskGrid;
    private Label? _diskEmpty;
    private ScrollContainer? _scroll;
    private GridContainer? _metrics, _detailGrid;
    private VBoxContainer? _settingsBox;
    private Control? _settingsCard;
    private bool _hostActive = true;
    private Button? _pause;
    private Button? _minimal, _thermalAdmin, _thermalDriver;
    private Control? _thermalHelp;
    private bool _minimalAvailable;
    private CheckButton? _desktop, _alerts;
    private SpinBox? _cpuLimit, _gpuLimit, _glassTransparency;
    private Color _paper = new("10151d"), _surface = new("192332"), _text = new("edf2f8"), _muted = new("95a7bc"), _accent = new("acc9e7"), _border = new("314155");
    private Color _mint = new("94d5bf"), _purple = new("beb2e0"), _gold = new("dfc39f");

    public void Configure(Node service, int mode = 0)
    {
        Disconnect(); _service = service as PcMonitorService; _mode = mode;
        if (_service != null) { _service.Updated += Refresh; _service.PreferencesChanged += Preferences; }
        if (IsNodeReady()) QueueBuild();
    }
    public void SetProfileId(string profileId) { _profileId = profileId; if (IsNodeReady()) Preferences(); }
    public void SetMinimalAvailable(bool value) { _minimalAvailable = value; if (_minimal != null) _minimal.Disabled = !value; }
    public void ShowSensorSettings() { _settingsOpen = true; if (_settingsCard != null) { _settingsCard.Show(); _scroll?.EnsureControlVisible(_settingsCard); } }
    public void ConfigureTheme(Color paper, Color surface, Color foreground, Color muted, Color accent, Color border)
    {
        (_paper, _surface, _text, _muted, _accent, _border) = (paper, surface, foreground, muted, accent, border);
        bool light = paper.R * .2126f + paper.G * .7152f + paper.B * .0722f > .5f;
        _mint = light ? new("257059") : new("94d5bf"); _purple = light ? new("7252a1") : new("beb2e0"); _gold = light ? new("8b641d") : new("dfc39f");
        if (IsNodeReady()) QueueBuild();
    }
    public override void _Ready() { Build(); Resized += LayoutColumns; }
    public void SetHostActive(bool value) => _hostActive = value;
    public override void _ExitTree() => Disconnect();
    private void Disconnect()
    {
        if (_service != null) { _service.Updated -= Refresh; _service.PreferencesChanged -= Preferences; _service.Subscribe(GetInstanceId(), false); }
        _visibleSubscribed = false;
    }
    public override void _Process(double delta)
    {
        _clock += delta;
        if (_clock < .4 || _service == null) return;
        _clock = 0;
        bool visible = _hostActive && IsVisibleInTree() && GetWindow().Visible && GetWindow().Mode != Window.ModeEnum.Minimized;
        if (visible != _visibleSubscribed) { _service.Subscribe(GetInstanceId(), visible); _visibleSubscribed = visible; }
        if (visible) Refresh();
    }
    private StyleBoxFlat Box(Color color, int radius = 12, int margin = 16) => new() {
        BgColor = color, BorderColor = _border, BorderWidthLeft = 1, BorderWidthTop = 1, BorderWidthRight = 1, BorderWidthBottom = 1,
        CornerRadiusTopLeft = radius, CornerRadiusTopRight = radius, CornerRadiusBottomLeft = radius, CornerRadiusBottomRight = radius,
        ContentMarginLeft = margin, ContentMarginRight = margin, ContentMarginTop = margin, ContentMarginBottom = margin };
    private VBoxContainer Column(Node parent, int gap = 10)
    { var v = new VBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill }; v.AddThemeConstantOverride("separation", gap); parent.AddChild(v); return v; }
    private HBoxContainer Row(Node parent, int gap = 10)
    { var h = new HBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill }; h.AddThemeConstantOverride("separation", gap); parent.AddChild(h); return h; }
    private HFlowContainer Flow(Node parent)
    { var flow = new HFlowContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill }; flow.AddThemeConstantOverride("h_separation", 10); flow.AddThemeConstantOverride("v_separation", 8); parent.AddChild(flow); return flow; }
    private void Spacer(Node parent) => parent.AddChild(new Control { SizeFlagsHorizontal = SizeFlags.ExpandFill });
    private Label Label(Node parent, string value, int size = 14, Color? color = null, string key = "", bool wrap = false)
    {
        var l = new Label { Text = value, MouseFilter = MouseFilterEnum.Ignore, AutowrapMode = wrap ? TextServer.AutowrapMode.WordSmart : TextServer.AutowrapMode.Off };
        l.AddThemeFontSizeOverride("font_size", size); l.AddThemeColorOverride("font_color", color ?? _text);
        if (_mode == 3)
        {
            bool light = _paper.R + _paper.G + _paper.B > 1.5f;
            l.AddThemeColorOverride("font_outline_color", light ? new Color(1, 1, 1, .65f) : new Color(0, 0, 0, .7f));
            l.AddThemeConstantOverride("outline_size", 1);
            l.AddThemeColorOverride("font_shadow_color", light ? new Color(1, 1, 1, .35f) : new Color(0, 0, 0, .5f));
            l.AddThemeConstantOverride("shadow_offset_y", 1);
        }
        parent.AddChild(l); if (key.Length > 0) { _labels[key] = l; l.Name = key; } return l;
    }
    private Button Button(Node parent, string value, Action pressed)
    { var b = new Button { Text = value, FocusMode = FocusModeEnum.None }; b.AddThemeFontSizeOverride("font_size", 12); b.Pressed += pressed; parent.AddChild(b); return b; }
    private VBoxContainer Card(Node parent, string title = "")
    {
        var p = new PanelContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill, SizeFlagsVertical = SizeFlags.Fill };
        p.AddThemeStyleboxOverride("panel", Box(_surface)); parent.AddChild(p); var c = Column(p);
        if (title.Length > 0) Label(c, title, 17); return c;
    }
    private OptionButton Choice(Node parent, string key, Action<string> changed)
    {
        var c = new OptionButton { SizeFlagsHorizontal = SizeFlags.ExpandFill, FitToLongestItem = false, CustomMinimumSize = new(120, 32) };
        c.AddThemeFontSizeOverride("font_size", 12); parent.AddChild(c); _choices[key] = c;
        c.ItemSelected += index => { if (_choiceIds.TryGetValue(key, out var ids) && index >= 0 && index < ids.Length) changed(ids[index]); };
        return c;
    }
    private void QueueBuild()
    {
        if (_buildQueued) return;
        _buildQueued = true;
        Callable.From(() => { _buildQueued = false; if (IsInsideTree()) Build(); }).CallDeferred();
    }
    private void Build()
    {
        foreach (var child in GetChildren()) { RemoveChild(child); child.QueueFree(); }
        _labels.Clear(); _choices.Clear(); _choiceIds.Clear(); _charts.Clear(); _diskRows.Clear(); _diskGrid = null; _diskEmpty = null; _scroll = null;
        _metrics = null; _detailGrid = null; _settingsBox = null; _settingsCard = null; _pause = null; _desktop = null; _alerts = null; _cpuLimit = null; _gpuLimit = null;
        _minimal = null; _thermalHelp = null; _thermalAdmin = null; _thermalDriver = null; _glassTransparency = null;
        int margin = _mode == 0 ? 22 : _mode == 3 ? 12 : 14;
        foreach (var side in new[] { "left", "right", "top", "bottom" }) AddThemeConstantOverride("margin_" + side, margin);
        var main = Column(this, _mode == 0 ? 16 : 9);
        if (_mode == 3) { BuildMinimal(main); Refresh(); return; }
        Container header = Flow(main);
        Label(header, "性能监控", _mode == 0 ? 26 : 16); Spacer(header);
        if (_mode == 0)
        {
            _minimal = Button(header, "极简模式", () => EmitSignal(SignalName.MinimalModeRequested));
            _minimal.Name = "OpenMinimalMonitor";
            _minimal.Disabled = !_minimalAvailable;
            _minimal.TooltipText = "以近身立绘和监控数据组成独立小窗；请先选择一位 2D 伙伴。";
            Choice(header, "interval", s => _service?.SetInterval(int.Parse(s))).CustomMinimumSize = new(88, 32);
            _pause = Button(header, "暂停", () => _service?.SetPaused(!_service.Paused));
            Button(header, "传感器设置", () => {
                _settingsOpen = !_settingsOpen;
                if (_settingsCard != null) _settingsCard.Visible = _settingsOpen;
                if (_settingsOpen) Callable.From(() => { if (_settingsCard != null) _scroll?.EnsureControlVisible(_settingsCard); }).CallDeferred();
            });
        }
        else
        {
            Button(header, _mode == 1 ? "展开" : "收起", () => _service?.SetExpandedFor(_profileId, _mode == 1)).Name = "ToggleMonitorDetails";
            var close = Button(header, "×", () => { GetViewport().SetInputAsHandled(); EmitSignal(SignalName.DismissRequested); });
            close.Name = "CloseMonitor";
            close.TooltipText = "关闭此伙伴的性能面板";
        }
        Label(main, "正在采样…", 12, _muted, "status", true);
        VBoxContainer content = main;
        if (_mode == 0)
        {
            var scroll = new ScrollContainer { SizeFlagsVertical = SizeFlags.ExpandFill, SizeFlagsHorizontal = SizeFlags.ExpandFill, HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled };
            _scroll = scroll;
            main.AddChild(scroll); content = Column(scroll, 16);
        }
        _metrics = new GridContainer { Columns = _mode == 0 ? 4 : 3, SizeFlagsHorizontal = SizeFlags.ExpandFill };
        _metrics.AddThemeConstantOverride("h_separation", _mode == 0 ? 14 : 10); content.AddChild(_metrics);
        string[] keys = _mode == 0 ? ["cpu", "memory", "gpu", "network"] : ["cpu", "memory", "gpu"];
        foreach (var key in keys)
        {
            var card = _mode == 0 ? Card(_metrics) : Column(_metrics, 2);
            Label(card, key switch { "cpu" => "CPU", "memory" => "内存", "gpu" => "GPU", _ => "下载" }, 12, _muted);
            Label(card, "—", _mode == 0 ? 34 : 25, key == "memory" ? _purple : key == "gpu" ? _mint : key == "network" ? _gold : _accent, key);
            var sub = Label(card, "等待采样", 11, _muted, key + "_sub"); sub.TextOverrunBehavior = TextServer.OverrunBehavior.TrimEllipsis;
            sub.CustomMinimumSize = new(_mode == 0 ? 120 : 75, 0); sub.SizeFlagsHorizontal = SizeFlags.ExpandFill;
        }
        if (_mode == 1)
        {
            main.AddChild(new HSeparator()); Label(main, "↓ —    ↑ —", 13, _text, "net_compact", true);
            Preferences(); Refresh(); return;
        }
        if (_mode == 0)
        {
            _detailGrid = new GridContainer { Columns = 2, SizeFlagsHorizontal = SizeFlags.ExpandFill };
            _detailGrid.AddThemeConstantOverride("h_separation", 14); _detailGrid.AddThemeConstantOverride("v_separation", 14); content.AddChild(_detailGrid);
            var trend = Card(_detailGrid); var tabs = Row(trend, 6); Label(tabs, "占用趋势", 17); Spacer(tabs);
            var chart = Chart(trend, 168, false);
            foreach (var (title, key) in new[] { ("CPU", "cpu"), ("内存", "memory"), ("GPU", "gpu"), ("网速", "network") })
                Button(tabs, title, () => { chart.Metric = key; chart.Ink = key == "memory" ? _purple : key == "gpu" ? _mint : key == "network" ? _gold : _accent; chart.QueueRedraw(); });
            Thermal(Card(_detailGrid, "温度与散热"));
            var network = Card(_detailGrid, "网络"); Choice(network, "network_device", s => _service?.SelectNetwork(s));
            Label(network, "↓ —    ↑ —", 23, _text, "net_compact"); var netChart = Chart(network, 100, false); netChart.Metric = "network"; netChart.Ink = _gold;
            var hardware = Card(_detailGrid, "显卡与显存"); Choice(hardware, "gpu_device", s => _service?.SelectGpu(s));
            Label(hardware, "专用显存 —", 14, _mint, "vram"); Label(hardware, "共享显存 —", 12, _muted, "shared");
            Label(hardware, "GPU 使用最忙引擎的占用率。显存按整张卡统计；共享显存单独显示。", 12, _muted, wrap: true);
            BuildDisks(Card(content, "硬盘 · 所有设备"));
            BuildSettings(content);
            Label(content, "", 11, _muted, "footer", true);
        }
        else
        {
            Label(content, "CPU · 最近 60 秒", 11, _muted); Chart(content, 64, true);
            content.AddChild(new HSeparator()); Thermal(content);
            content.AddChild(new HSeparator()); Label(content, "↓ —    ↑ —", 15, _text, "net_compact", true);
            Label(content, "专用显存 —", 11, _muted, "vram"); BuildDisks(content);
            Button(content, "在大厅查看详情与设置", () => EmitSignal(SignalName.HallRequested));
        }
        Preferences(); LayoutColumns(); Refresh();
    }
    private MonitorChart Chart(Node parent, int height, bool compact)
    {
        var chart = new MonitorChart { Service = _service, Compact = compact, Ink = _accent, Grid = _border, Muted = _muted,
            SizeFlagsHorizontal = SizeFlags.ExpandFill, CustomMinimumSize = new(180, height) };
        parent.AddChild(chart); _charts.Add(chart); return chart;
    }
    private void Thermal(Node parent)
    {
        var row = Row(parent, 14);
        foreach (var key in new[] { "cpu", "gpu" })
        { var c = Column(row, 3); Label(c, key.ToUpperInvariant() + " 温度", 11, _muted); Label(c, "—", _mode == 0 ? 29 : 22, _gold, key + "_temp"); }
        Label(parent, "CPU 风扇    — 未提供", 12, _text, "cpu_fan");
        Label(parent, "GPU 风扇    — 未提供", 12, _text, "gpu_fan");
        if (_mode == 0) Label(parent, "机箱风扇    — 未提供", 12, _muted, "other_fans", true);
        var note = Label(parent, "正在读取温度与风扇…", 11, _muted, "sensor_status", true);
        if (_mode != 0) note.MaxLinesVisible = 2;
        if (_mode == 0)
        {
            var help = Column(parent, 6); _thermalHelp = help; help.Name = "CpuTemperatureHelp";
            Label(help, "", 12, _gold, "cpu_help", true);
            var actions = Flow(help);
            _thermalDriver = Button(actions, "安装温度组件", () => _service?.InstallSensorDriver());
            _thermalDriver.TooltipText = "使用随包安装器，或下载校验后的官方 PawnIO。安装会新增 Windows 驱动，并弹出管理员授权。";
            _thermalAdmin = Button(actions, "启用高级读取", () => _service?.RestartSensors(true));
            Button(actions, "重新检测", () => _service?.RestartSensors(false));
        }
    }
    private static void OpenDriverPage() => OS.ShellOpen("https://github.com/namazso/PawnIO.Setup/releases/latest");
    private void BuildMinimal(Node parent)
    {
        foreach (var (name, key, color) in new[] { ("CPU", "cpu", _accent), ("GPU", "gpu", _mint), ("内存", "memory", _purple) })
        {
            var row = Row(parent, 8);
            Label(row, name, 12, _muted).CustomMinimumSize = new(36, 0);
            Label(row, "—", 19, color, key).CustomMinimumSize = new(43, 0);
            var detail = Label(row, "—", 11, _muted, key + "_sub");
            detail.SizeFlagsHorizontal = SizeFlags.ExpandFill; detail.HorizontalAlignment = HorizontalAlignment.Right;
            detail.TextOverrunBehavior = TextServer.OverrunBehavior.TrimEllipsis;
        }
        Label(parent, "显存 —", 11, _muted, "vram", true);
        MinimalSeparator(parent);
        var network = Row(parent, 8); Label(network, "↓ —", 13, _text, "download").SizeFlagsHorizontal = SizeFlags.ExpandFill;
        Label(network, "↑ —", 13, _text, "upload");
        Label(parent, "", 11, _muted, "fans", true);
        MinimalSeparator(parent); BuildDisks(parent);
        Label(parent, "", 11, _gold, "status", true);
    }
    private void MinimalSeparator(Node parent)
    {
        var line = new HSeparator();
        line.AddThemeStyleboxOverride("separator", new StyleBoxLine { Color = new(_text, .18f), Thickness = 1 });
        parent.AddChild(line);
    }
    private void BuildSettings(Node parent)
    {
        _settingsBox = Card(parent, "温度、风扇与显示设置"); _settingsCard = _settingsBox.GetParent<Control>(); _settingsCard.Visible = _settingsOpen;
        var glass = Flow(_settingsBox);
        Label(glass, "极简玻璃", 12, _muted);
        Choice(glass, "minimal_theme", s => _service?.SetMinimalAppearance(s, _service.Settings.MinimalOpacity));
        Label(glass, "背景透明度", 12, _muted);
        _glassTransparency = new SpinBox { MinValue = 65, MaxValue = 95, Step = 1, Format = "%d%%", CustomMinimumSize = new(88, 32) };
        glass.AddChild(_glassTransparency);
        _glassTransparency.ValueChanged += value => _service?.SetMinimalAppearance(_service.Settings.MinimalTheme, 1 - value / 100);
        Label(_settingsBox, "只调整极简窗口的玻璃底色；立绘和文字保持清晰。也可在极简窗口右键切换亮色或暗色。", 11, _muted, wrap: true);
        var toggles = Flow(_settingsBox);
        _desktop = new CheckButton { Text = "显示此伙伴的性能悬浮卡" }; toggles.AddChild(_desktop); _desktop.Toggled += b => _service?.SetDesktopVisibleFor(_profileId, b);
        Button(toggles, "重新读取", () => _service?.RestartSensors(false));
        var admin = Button(toggles, "启用高级读取", () => _service?.RestartSensors(true)); admin.TooltipText = "仅提升传感器进程的权限，Windows 将弹出授权提示。";
        Button(toggles, "安装驱动说明", OpenDriverPage);
        Label(_settingsBox, "", 12, _gold, "driver_status", true);
        Label(_settingsBox, "普通权限下会显示能够读取的项目。高级读取仍缺少 CPU 温度或主板风扇时，可能需要安装 PawnIO 或设备未提供传感器。", 12, _muted, wrap: true);
        foreach (var (key, name) in new[] { ("cpu_temp", "CPU 温度来源"), ("gpu_temp", "GPU 温度来源"), ("cpu_fan", "CPU 风扇绑定") })
        { var row = Row(_settingsBox); Label(row, name, 12, _muted).CustomMinimumSize = new(125, 0); Choice(row, key, s => _service?.SelectSensor(key, s)); }
        Label(_settingsBox, "Fan #1 等通用名称不会自动当作 CPU 风扇。请按主板接口选择；0 RPM 表示有效的停转读数。", 11, _muted, wrap: true);
        var alerts = Row(_settingsBox);
        _alerts = new CheckButton { Text = "高温提醒" }; alerts.AddChild(_alerts);
        Label(alerts, "CPU", 12, _muted); _cpuLimit = Threshold(alerts); Label(alerts, "GPU", 12, _muted); _gpuLimit = Threshold(alerts);
        _alerts.Toggled += _ => SaveAlerts(); _cpuLimit.ValueChanged += _ => SaveAlerts(); _gpuLimit.ValueChanged += _ => SaveAlerts();
        Label(_settingsBox, "温度连续超过自定阈值 10 秒后提醒，两次提醒至少间隔 2 分钟。阈值可按设备调整。", 11, _muted, wrap: true);
    }
    private SpinBox Threshold(Node parent)
    { var s = new SpinBox { MinValue = 40, MaxValue = 110, Step = 1, Format = "%d °C", CustomMinimumSize = new(92, 32) }; parent.AddChild(s); return s; }
    private void SaveAlerts() { if (_alerts != null && _cpuLimit != null && _gpuLimit != null) _service?.SetAlerts(_alerts.ButtonPressed, _cpuLimit.Value, _gpuLimit.Value); }
    private void Preferences()
    {
        if (_service == null) return;
        if (_mode is 1 or 2 && (_service.IsExpandedFor(_profileId) ? 2 : 1) != _mode) { _mode = _service.IsExpandedFor(_profileId) ? 2 : 1; QueueBuild(); return; }
        if (_desktop != null) { _desktop.Disabled = _profileId.Length == 0; _desktop.SetPressedNoSignal(_service.IsDesktopVisibleFor(_profileId)); }
        _alerts?.SetPressedNoSignal(_service.Settings.Alerts);
        _cpuLimit?.SetValueNoSignal(_service.Settings.CpuLimit); _gpuLimit?.SetValueNoSignal(_service.Settings.GpuLimit);
        _glassTransparency?.SetValueNoSignal(Math.Round((1 - _service.Settings.MinimalOpacity) * 100));
        Refresh();
    }
    private void LayoutColumns()
    {
        if (_mode == 0) {
            if (_metrics != null) _metrics.Columns = Size.X < 720 ? 2 : 4;
            if (_detailGrid != null) _detailGrid.Columns = Size.X < 850 ? 1 : 2;
            if (_diskGrid != null) _diskGrid.Columns = Size.X < 720 ? 1 : 2;
        }
        else if (_metrics != null) _metrics.Columns = Size.X < 300 ? 2 : 3;
    }
    private void BuildDisks(Node parent)
    {
        _diskEmpty = Label(parent, "正在读取硬盘…", 12, _muted);
        _diskGrid = new GridContainer { Columns = _mode == 0 && Size.X >= 720 ? 2 : 1, SizeFlagsHorizontal = SizeFlags.ExpandFill };
        _diskGrid.AddThemeConstantOverride("h_separation", 12); _diskGrid.AddThemeConstantOverride("v_separation", 10); parent.AddChild(_diskGrid);
    }
    private void RefreshDisks(MonitorDevice[] disks, bool stale)
    {
        if (_diskGrid == null) return;
        if (!_diskRows.Keys.OrderBy(x => x).SequenceEqual(disks.Select(d => d.Id).OrderBy(x => x)))
        {
            foreach (var child in _diskGrid.GetChildren()) { _diskGrid.RemoveChild(child); child.QueueFree(); }
            _diskRows.Clear();
            foreach (var disk in disks)
            {
                var column = Column(_diskGrid, 5);
                var header = Row(column); var title = Label(header, disk.Name, 12); title.SizeFlagsHorizontal = SizeFlags.ExpandFill;
                title.TextOverrunBehavior = TextServer.OverrunBehavior.TrimEllipsis;
                var busy = Label(header, "—", 13, _accent);
                var bar = new ProgressBar { ShowPercentage = false, CustomMinimumSize = new(_mode == 3 ? 100 : 160, 3), SizeFlagsHorizontal = SizeFlags.ExpandFill };
                var track = Box(_mode == 3 ? new Color(_text, .1f) : _paper, 2, 0); track.SetBorderWidthAll(0);
                var fill = Box(_mode == 3 ? new Color(_accent, .8f) : _accent, 2, 0); fill.SetBorderWidthAll(0);
                bar.AddThemeStyleboxOverride("background", track); bar.AddThemeStyleboxOverride("fill", fill); column.AddChild(bar);
                var io = Label(column, "读 —    写 —", 11, _muted, wrap: true);
                _diskRows[disk.Id] = (busy, io, bar);
            }
        }
        if (_diskEmpty != null) { _diskEmpty.Visible = disks.Length == 0; _diskEmpty.Text = "暂无可用的硬盘计数器"; }
        foreach (var disk in disks)
        {
            var row = _diskRows[disk.Id]; row.Busy.Text = Percent(stale ? null : disk.Usage);
            row.Io.Text = "读 " + Rate(stale ? null : disk.Receive) + "    写 " + Rate(stale ? null : disk.Send);
            row.Bar.Value = !stale ? disk.Usage ?? 0 : 0; row.Bar.Visible = !stale && disk.Usage != null;
        }
    }
    private void Put(string key, string value, string tooltip = "")
    { if (_labels.TryGetValue(key, out var label)) { label.Text = value; label.TooltipText = tooltip; label.MouseFilter = tooltip.Length > 0 ? MouseFilterEnum.Pass : MouseFilterEnum.Ignore; } }
    private void Options(string key, IEnumerable<(string Id, string Name)> entries, string selected, string automatic)
    {
        if (!_choices.TryGetValue(key, out var button)) return;
        var items = new List<(string Id, string Name)>(); if (automatic.Length > 0) items.Add(("", automatic)); items.AddRange(entries);
        if (selected.Length > 0 && !items.Any(x => x.Id == selected)) items.Add((selected, "已断开 · 当前自动匹配"));
        if (items.Count == 0) items.Add(("", "未提供"));
        var ids = items.Select(i => i.Id).ToArray();
        if (!_choiceIds.TryGetValue(key, out var old) || !old.SequenceEqual(ids))
        { button.Clear(); foreach (var item in items) button.AddItem(item.Name); _choiceIds[key] = ids; }
        button.Select(Math.Max(0, Array.IndexOf(ids, selected)));
        button.TooltipText = button.Text;
    }
    private void Refresh()
    {
        if (_service == null || !IsNodeReady()) return;
        var s = _service.Latest; bool stale = _service.Stale && !_service.Paused;
        var gpu = _service.Gpu(); var nic = _service.Network();
        string status = !_service.Supported ? "PC 性能监控仅支持 Windows" : _service.Paused ? "采样已暂停" : stale ? "数据已过期 · 正在等待更新" : s.Cpu == null ? "正在采样…" : "● 实时监控 · 每 " + _service.Settings.Interval + " 秒刷新";
        if (_service.AlertMessage.Length > 0) status = _service.AlertMessage;
        if (_mode == 3 && !_service.Paused && !stale && s.Cpu != null && _service.AlertMessage.Length == 0) status = "";
        Put("status", status);
        if (_mode == 3 && _labels.TryGetValue("status", out var statusLabel)) statusLabel.Visible = status.Length > 0;
        Put("cpu", Percent(stale ? null : s.Cpu)); Put("memory", Percent(stale ? null : s.MemoryPercent)); Put("gpu", Percent(stale ? null : gpu?.Usage));
        Put("cpu_sub", "温度 " + (_service.CpuTemperature?.Value is { } cpuTemp ? Temperature(cpuTemp) : _service.CpuTemperatureState),
            _service.CpuTemperature?.Value == null ? _service.CpuTemperatureHelp : Source(_service.CpuTemperature));
        Put("memory_sub", Bytes(stale ? null : s.MemoryUsed) + " / " + Bytes(s.MemoryTotal));
        Put("gpu_sub", "温度 " + Temperature(_service.GpuTemperature?.Value), gpu?.Name ?? "未提供显卡计数器");
        Put("network", Rate(stale ? null : nic?.Receive)); Put("network_sub", "↑ " + Rate(stale ? null : nic?.Send), nic?.Name ?? "未连接");
        Put("net_compact", "↓ " + Rate(stale ? null : nic?.Receive) + "    ↑ " + Rate(stale ? null : nic?.Send), nic?.Name ?? "未连接");
        Put("download", "↓ " + Rate(stale ? null : nic?.Receive), nic?.Name ?? "未连接");
        Put("upload", "↑ " + Rate(stale ? null : nic?.Send), nic?.Name ?? "未连接");
        Put("vram", "专用显存 " + Bytes(stale ? null : gpu?.Used) + " / " + Bytes(gpu?.Total)); Put("shared", "共享显存 " + Bytes(stale ? null : gpu?.Shared));
        RefreshDisks(s.Disks, stale);
        Put("cpu_temp", _service.CpuTemperature?.Value is { } temperature ? Temperature(temperature) : _service.CpuTemperatureState,
            _service.CpuTemperature?.Value == null ? _service.CpuTemperatureHelp : Source(_service.CpuTemperature));
        Put("gpu_temp", Temperature(_service.GpuTemperature?.Value), Source(_service.GpuTemperature));
        Put("cpu_fan", "CPU 风扇    " + Fan(_service.CpuFan), Source(_service.CpuFan));
        Put("gpu_fan", "GPU 风扇    " + Fan(_service.GpuFan), Source(_service.GpuFan));
        Put("fans", "风扇  CPU " + Fan(_service.CpuFan) + "  · GPU " + Fan(_service.GpuFan));
        if (_thermalHelp != null) _thermalHelp.Visible = _service.CpuTemperature?.Value == null;
        Put("cpu_help", (_service.DriverInstallStatus.Length > 0 ? _service.DriverInstallStatus + "\n" : "") + _service.CpuTemperatureHelp);
        Put("driver_status", _service.DriverInstallStatus);
        if (_labels.TryGetValue("driver_status", out var driverStatus)) driverStatus.Visible = _service.DriverInstallStatus.Length > 0;
        if (_thermalDriver != null) {
            _thermalDriver.Visible = _service.Sensors.Connected && (!_service.Sensors.DriverInstalled || _service.InstallingDriver);
            _thermalDriver.Disabled = _service.InstallingDriver;
            _thermalDriver.Text = _service.InstallingDriver ? "正在安装…" : "安装温度组件";
        }
        if (_thermalAdmin != null) _thermalAdmin.Disabled = !_service.Sensors.Connected || !_service.Sensors.DriverInstalled;
        var others = _service.OtherFans;
        Put("other_fans", others.Length == 0 ? "机箱风扇    — 未提供" : string.Join("\n", others.Take(4).Select(f => f.Name + "    " + Fan(f))));
        Put("sensor_status", _service.SensorStale ? "传感器数据已过期，等待重新连接。" : _service.Sensors.Status);
        Put("footer", _service.PreferenceError.Length > 0 ? _service.PreferenceError : s.Error.Length > 0 ? s.Error : "最近更新 " + s.Time.ToLocalTime().ToString("HH:mm:ss") + " · 本机状态");
        if (_pause != null) _pause.Text = _service.Paused ? "继续采样" : "暂停采样";
        Options("interval", new[] { ("1", "每 1 秒"), ("2", "每 2 秒"), ("5", "每 5 秒") }, _service.Settings.Interval.ToString(), "");
        Options("minimal_theme", new[] { ("follow", "跟随应用主题"), ("light", "亮色玻璃"), ("dark", "暗色玻璃") }, _service.Settings.MinimalTheme, "");
        Options("gpu_device", s.Gpus.Select(d => (d.Id, d.Name)), _service.Settings.Gpu, "自动 · 第一张显卡");
        Options("network_device", s.Networks.Select(d => (d.Id, d.Name)), _service.Settings.Network, "自动 · 活动路由网卡");
        foreach (var (key, type, selected) in new[] { ("cpu_temp", "Temperature", _service.Settings.CpuTemperature), ("gpu_temp", "Temperature", _service.Settings.GpuTemperature), ("cpu_fan", "Fan", _service.Settings.CpuFan) })
            Options(key, _service.Sensors.Sensors.Where(r => r.Type == type && (key != "gpu_temp" || r.Kind == "gpu") && (key != "cpu_temp" || r.Kind == "cpu"))
                .Select(r => (r.Id, r.DeviceName + " · " + r.Name)), selected, "自动匹配");
        foreach (var chart in _charts) chart.QueueRedraw();
    }
    private static string Source(SensorReading? s) => s == null ? "未找到可读取的传感器，可在设置中选择来源。" : s.DeviceName + " · " + s.Name;
    private static string Percent(double? n) => n is { } v ? v.ToString("0") + "%" : "—";
    private static string Temperature(double? n) => n is { } v ? v.ToString("0.#") + " °C" : "—";
    private static string Fan(SensorReading? s) => s?.Value is { } v ? v.ToString("N0") + " " + s.Unit : "— 未提供";
    public static string Bytes(double? n) => n is { } v ? (v / 1073741824).ToString("0.0") + " GiB" : "—";
    public static string Rate(double? n) => n is not { } v ? "—" : v >= 1048576 ? (v / 1048576).ToString("0.0") + " MiB/s" : (v / 1024).ToString("0") + " KiB/s";
}
