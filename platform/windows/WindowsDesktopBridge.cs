using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using Godot;

namespace GdPal.Platform;

/// <summary>Platform queries; native desktop interaction is added behind this boundary.</summary>
[GlobalClass]
public partial class WindowsDesktopBridge : Node
{
    private Godot.Collections.Array<Godot.Collections.Dictionary> _surfaceCache = new();
    private ulong _surfaceCacheAt;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left, Top, Right, Bottom;
        public readonly Rect2I Rect => new(Left, Top, Right - Left, Bottom - Top);
    }

    private delegate bool EnumWindowProc(nint window, nint parameter);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowProc callback, nint parameter);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(nint window);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint window, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(nint window, StringBuilder name, int count);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(nint window, int index);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(nint window, out NativeRect rect);

    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int GetFrameBounds(nint window, int attribute, out NativeRect rect, int size);

    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int GetCloaked(nint window, int attribute, out int cloaked, int size);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out NativePoint point);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

    [DllImport("gdi32.dll")]
    private static extern nint CreateRectRgn(int left, int top, int right, int bottom);

    [DllImport("gdi32.dll")]
    private static extern int CombineRgn(nint destination, nint first, nint second, int mode);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(nint handle);

    [DllImport("user32.dll")]
    private static extern int SetWindowRgn(nint window, nint region, [MarshalAs(UnmanagedType.Bool)] bool redraw);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(nint window, int command);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(nint window);

    // Godot's root Window cannot be hidden with Window.Hide(). Keep its HWND
    // alive so the notification icon and independent desktop windows keep working.
    public bool SetMainWindowVisible(bool visible)
    {
        if (!OS.HasFeature("windows") || DisplayServer.GetName() == "headless" || Engine.IsEmbeddedInEditor())
            return false;
        var window = (nint)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        if (window == 0) return false;
        ShowWindow(window, visible ? 5 : 0); // SW_SHOW / SW_HIDE; retain placement and maximized state.
        return IsWindowVisible(window) == visible;
    }

    public bool IsPrimaryButtonDown() => OS.HasFeature("windows")
        ? (GetAsyncKeyState(1) & 0x8000) != 0
        : Input.IsMouseButtonPressed(MouseButton.Left);

    // Windows clips drawing as well as input to this region. Callers supply
    // conservative model bounds and every visible control, never a tight silhouette.
    public bool SetInputRegions(int windowId, Godot.Collections.Array<Rect2> regions)
    {
        if (!OS.HasFeature("windows") || DisplayServer.GetName() == "headless")
            return false;
        var window = (nint)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle, windowId);
        if (window == 0) return false;
        if (regions.Count == 0) return SetWindowRgn(window, 0, true) != 0;

        nint combined = CreateRectRgn(0, 0, 0, 0);
        if (combined == 0) return false;
        bool transferred = false;
        try
        {
            foreach (var bounds in regions)
            {
                if (bounds.Size.X <= 0 || bounds.Size.Y <= 0) continue;
                nint part = CreateRectRgn((int)Math.Floor(bounds.Position.X), (int)Math.Floor(bounds.Position.Y),
                    (int)Math.Ceiling(bounds.End.X), (int)Math.Ceiling(bounds.End.Y));
                if (part == 0) return false;
                try { if (CombineRgn(combined, combined, part, 2) == 0) return false; }
                finally { DeleteObject(part); }
            }
            transferred = SetWindowRgn(window, combined, true) != 0;
            return transferred;
        }
        finally
        {
            // SetWindowRgn takes ownership on success; otherwise we own the handle.
            if (!transferred) DeleteObject(combined);
        }
    }

    public Vector2 GetGlobalCursorPosition()
    {
        if (OS.HasFeature("windows") && GetCursorPos(out var point))
            return new Vector2(point.X, point.Y);

        return DisplayServer.MouseGetPosition();
    }

    // Physical screen coordinates, matching GetCursorPos and the native pet windows.
    // EnumWindows walks front-to-back. Subtract higher windows from each top edge
    // so a pet cannot attach to a border covered by another application.
    public Godot.Collections.Array<Godot.Collections.Dictionary> GetDesktopSurfaces()
    {
        if (!OS.HasFeature("windows") || DisplayServer.GetName() == "headless")
            return new();
        var now = Time.GetTicksMsec();
        if (_surfaceCacheAt != 0 && now - _surfaceCacheAt < 150) return _surfaceCache;
        var surfaces = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        var occluders = new List<Rect2I>();
        var ownProcess = (uint)System.Environment.ProcessId;
        EnumWindows((window, _) =>
        {
            if (!IsWindowVisible(window) || IsIconic(window)) return true;
            GetWindowThreadProcessId(window, out var process);
            if (process == ownProcess) return true;
            if (GetCloaked(window, 14, out var cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            var classBuffer = new StringBuilder(256);
            GetClassName(window, classBuffer, classBuffer.Capacity);
            var windowClass = classBuffer.ToString();
            if (windowClass is "Progman" or "WorkerW") return true;
            var taskbar = windowClass is "Shell_TrayWnd" or "Shell_SecondaryTrayWnd";
            NativeRect native;
            if (taskbar)
            {
                if (!GetWindowRect(window, out native)) return true;
            }
            else if (GetFrameBounds(window, 9, out native, Marshal.SizeOf<NativeRect>()) != 0 &&
                     !GetWindowRect(window, out native)) return true;
            var rect = native.Rect;
            if (rect.Size.X <= 0 || rect.Size.Y <= 0) return true;
            // Tool windows still occlude, but are not stable surfaces to perch on.
            var candidate = taskbar || ((GetWindowLong(window, -20) & 0x80) == 0 && rect.Size.Y >= 80);
            if (taskbar && (rect.Size.Y < 8 || rect.Size.Y > rect.Size.X)) candidate = false;
            if (candidate && rect.Size.X >= 120)
            {
                var segments = new List<(int Left, int Right)> { (rect.Position.X, rect.End.X) };
                foreach (var cover in occluders)
                {
                    if (cover.Position.Y > rect.Position.Y + 2 || cover.End.Y <= rect.Position.Y) continue;
                    var remaining = new List<(int Left, int Right)>();
                    foreach (var segment in segments)
                    {
                        if (cover.End.X <= segment.Left || cover.Position.X >= segment.Right)
                            remaining.Add(segment);
                        else
                        {
                            if (cover.Position.X > segment.Left) remaining.Add((segment.Left, cover.Position.X));
                            if (cover.End.X < segment.Right) remaining.Add((cover.End.X, segment.Right));
                        }
                    }
                    segments = remaining;
                }
                foreach (var segment in segments)
                {
                    if (segment.Right - segment.Left < 120) continue;
                    surfaces.Add(new Godot.Collections.Dictionary
                    {
                        ["id"] = $"{window}:{process}",
                        ["kind"] = taskbar ? "taskbar" : "window",
                        ["left"] = segment.Left, ["right"] = segment.Right,
                        ["y"] = rect.Position.Y,
                        ["source_left"] = rect.Position.X, ["source_width"] = rect.Size.X,
                    });
                }
            }
            occluders.Add(rect);
            return true;
        }, 0);
        _surfaceCache = surfaces;
        _surfaceCacheAt = now;
        return surfaces;
    }

    public Godot.Collections.Dictionary GetPlatformInfo() => new()
    {
        ["os"] = OS.GetName(),
        ["windows"] = OS.HasFeature("windows"),
        ["display_server"] = DisplayServer.GetName(),
        ["desktop_passthrough_implemented"] = true,
        ["passthrough_mode"] = "conservative_window_regions",
        ["native_window_available"] = OS.HasFeature("windows") && DisplayServer.GetName() != "headless",
        ["external_window_attachment_implemented"] = OS.HasFeature("windows"),
    };
}
