using System;
using Godot;
using GdPal.Desktop;

namespace GdPal.Monitoring;

[GlobalClass]
public partial class PcMonitorWindow : Window
{
    [Signal] public delegate void HallRequestedEventHandler();
    private PcMonitorService? _service;
    private Window? _host;
    private PcMonitorPanel? _panel;
    private PanelContainer? _background;
    private double _elapsed;
    private string _profileId = "";
    private bool _closeQueued, _placed;
    private Rect2I _lastAnchor;
    private Vector2I _lastRequested;
    private Color _paper = new("10151d"), _surface = new("192332"), _text = new("edf2f8"), _muted = new("95a7bc"), _accent = new("acc9e7"), _border = new("314155");
    public void Configure(Node service, Window host, string profileId) { _service = service as PcMonitorService; _host = host; _profileId = profileId; }
    public void ConfigureTheme(Color paper, Color surface, Color text, Color muted, Color accent, Color border)
    {
        (_paper, _surface, _text, _muted, _accent, _border) = (paper, surface, text, muted, accent, border);
        if (_panel != null) _panel.ConfigureTheme(paper, surface, text, muted, accent, border);
        Style();
    }
    public override void _Ready()
    {
        Title = "GD Pal · 性能监控"; Borderless = true; Transparent = true; TransparentBg = true;
        AlwaysOnTop = true; Unresizable = true; Unfocusable = false; Transient = false;
        ContentScaleMode = ContentScaleModeEnum.Disabled; ContentScaleSize = Vector2I.Zero;
        // A child Window otherwise inherits the pet's 2D canvas and can draw UI into both windows.
        World2D = new World2D();
        Theme = _host?.Theme; Size = new(368, 200);
        _background = new PanelContainer(); AddChild(_background); _background.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var scroll = new ScrollContainer { HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
        _background.AddChild(scroll);
        _panel = new PcMonitorPanel { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
        _panel.SetProfileId(_profileId);
        _panel.ConfigureTheme(_paper, _surface, _text, _muted, _accent, _border);
        if (_service != null) _panel.Configure(_service, _service.IsExpandedFor(_profileId) ? 2 : 1);
        scroll.AddChild(_panel);
        _panel.HallRequested += () => EmitSignal(SignalName.HallRequested);
        _panel.DismissRequested += ClosePanel;
        CloseRequested += ClosePanel;
        if (_service != null) _service.PreferencesChanged += PreferencesChanged;
        Style(); Follow();
    }
    private void Style()
    {
        if (_background == null) return;
        _background.AddThemeStyleboxOverride("panel", new StyleBoxFlat { BgColor = new(_surface, .98f), BorderColor = _border,
            BorderWidthLeft = 1, BorderWidthTop = 1, BorderWidthRight = 1, BorderWidthBottom = 1,
            CornerRadiusTopLeft = 14, CornerRadiusTopRight = 14, CornerRadiusBottomLeft = 14, CornerRadiusBottomRight = 14 });
    }
    public override void _Process(double delta) { _elapsed += delta; if (_elapsed >= .1) { _elapsed = 0; Follow(); } }
    public override void _ExitTree() { if (_service != null) _service.PreferencesChanged -= PreferencesChanged; }
    public void ClosePanel()
    {
        bool alreadyQueued = _closeQueued;
        _closeQueued = true;
        SetInputAsHandled();
        _service?.SetDesktopVisibleFor(_profileId, false);
        if (alreadyQueued) return;
        // Complete closing after the button's input dispatch, before another window can receive it.
        Callable.From(() => {
            if (!IsInsideTree()) return;
            if (_service?.IsDesktopVisibleFor(_profileId) != true) { Hide(); _panel?.SetHostActive(false); }
            _closeQueued = false;
        }).CallDeferred();
    }
    private void PreferencesChanged()
    {
        if (!_closeQueued && _service?.IsDesktopVisibleFor(_profileId) != true) { Hide(); _panel?.SetHostActive(false); }
        // Reposition after layout has settled, not inside another panel's button callback.
    }
    public void UpdatePlacement() => Follow();
    private void Follow()
    {
        if (_closeQueued) return;
        if (_service == null || _host == null || !IsInstanceValid(_host) || _panel == null) { Hide(); return; }
        bool show = _service.IsDesktopVisibleFor(_profileId) && _host.IsInsideTree() && _host.Visible && _host.Mode != ModeEnum.Minimized && !_host.Call("is_minimal_mode").AsBool();
        if (!show || DisplayServer.GetName() == "headless") { Hide(); _panel.SetHostActive(false); return; }
        var area = _host.Call("current_work_area").AsRect2I();
        var occupied = new Rect2I();
        if (_host.HasMeta("pal_chat_window") && _host.GetMeta("pal_chat_window").AsGodotObject() is Window chat && IsInstanceValid(chat) && chat.Visible)
            occupied = new(chat.Position, chat.Size);
        int height = Math.Max(170, (int)Math.Ceiling(_panel.GetCombinedMinimumSize().Y) + 4);
        var anchor = new Rect2I(_host.Position, _host.Size);
        var requested = new Vector2I(380, height);
        var preferred = _placed ? new Rect2I(Position + anchor.Position - _lastAnchor.Position, requested == _lastRequested ? Size : requested) : default;
        var placement = DesktopPopupLayout.Fit(area, anchor, requested, occupied, new(280, 128), preferred);
        if (placement.Size.X <= 0 || placement.Size.Y <= 0) { Hide(); _panel.SetHostActive(false); return; }
        if (Size != placement.Size) Size = placement.Size;
        if (Position != placement.Position) Position = placement.Position;
        _placed = true; _lastAnchor = anchor; _lastRequested = requested;
        _panel.SetHostActive(true);
        if (!Visible) Show();
    }
}
