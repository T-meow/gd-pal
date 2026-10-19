using System;
using System.Linq;
using Godot;

namespace GdPal.Monitoring;

public partial class MonitorChart : Control
{
    public PcMonitorService? Service;
    public string Metric = "cpu";
    public Color Ink = new("acc9e7"), Grid = new("314155"), Muted = new("95a7bc");
    public bool Compact;
    public override void _Ready() { MouseFilter = MouseFilterEnum.Ignore; Resized += QueueRedraw; }
    private double? Value(MonitorSnapshot s) => Metric switch
    { "memory" => s.MemoryPercent, "gpu" => Service?.Gpu(s)?.Usage, "network" => Service?.Network(s)?.Receive / 1048576, _ => s.Cpu };
    public override void _Draw()
    {
        if (Service == null) return;
        float left = Compact ? 0 : 32, right = Size.X - 4, top = Compact ? 3 : 15, bottom = Size.Y - (Compact ? 4 : 24);
        if (right <= left || bottom <= top) return;
        var history = Service.History.ToArray();
        double max = Metric == "network" ? Math.Max(1, history.Select(s => Value(s) ?? 0).DefaultIfEmpty(0).Max() * 1.2) : 100;
        var font = GetThemeFont("font", "Label");
        for (int i = 0; i < 3; i++)
        {
            float y = top + (bottom - top) * i / 2;
            DrawLine(new(left, y), new(right, y), Grid, 1);
            if (!Compact) DrawString(font, new(0, y + 4), (max * (2 - i) / 2).ToString("0.#"), fontSize: 10, modulate: Muted);
        }
        DateTimeOffset now = Service.Paused && history.Length > 0 ? history[^1].Time : DateTimeOffset.UtcNow;
        Vector2? previous = null; DateTimeOffset previousTime = default;
        foreach (var sample in history)
        {
            var value = Value(sample); double age = (now - sample.Time).TotalSeconds;
            if (value == null || age > 60) { previous = null; continue; }
            var p = new Vector2(left + (right - left) * (float)(1 - age / 60), bottom - (bottom - top) * (float)Math.Clamp(value.Value / max, 0, 1));
            if (previous is { } point && sample.Time - previousTime <= TimeSpan.FromSeconds(Service.Settings.Interval * 3 + 1)) DrawLine(point, p, Ink, 2, true);
            previous = p; previousTime = sample.Time;
        }
        if (previous is { } last) DrawCircle(last, 3, Ink);
        if (!Compact)
        {
            DrawString(font, new(left, Size.Y - 4), "60 秒前", fontSize: 10, modulate: Muted);
            string end = Metric == "network" ? "MiB/s · 现在" : "% · 现在";
            DrawString(font, new(Math.Max(left, right - 76), Size.Y - 4), end, fontSize: 10, modulate: Muted);
        }
    }
}
