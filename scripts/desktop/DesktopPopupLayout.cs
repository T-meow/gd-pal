using System;
using System.Collections.Generic;
using Godot;

namespace GdPal.Desktop;

/// <summary>Arrange screen-space windows in free rectangles, never by clamping across the pet.</summary>
[GlobalClass]
public partial class DesktopPopupLayout : RefCounted
{
    public Rect2I Arrange(Rect2I workArea, Rect2I character, Vector2I requested, Rect2I occupied, Vector2I minimum)
        => Fit(workArea, character, requested, occupied, minimum);
    public Rect2I ArrangeWithPreference(Rect2I workArea, Rect2I character, Vector2I requested, Rect2I occupied, Vector2I minimum, Rect2I preferred)
        => Fit(workArea, character, requested, occupied, minimum, preferred);

    public static Rect2I Fit(Rect2I workArea, Rect2I character, Vector2I requested, Rect2I occupied, Vector2I minimum, Rect2I preferred = default)
    {
        const int margin = 8, gap = 10;
        var bounds = new Rect2I(workArea.Position + new Vector2I(margin, margin),
            new Vector2I(Math.Max(1, workArea.Size.X - margin * 2), Math.Max(1, workArea.Size.Y - margin * 2)));
        var characterClearance = new Rect2I(character.Position - new Vector2I(gap, gap), character.Size + new Vector2I(gap * 2, gap * 2));
        var occupiedClearance = new Rect2I(occupied.Position - new Vector2I(gap, gap), occupied.Size + new Vector2I(gap * 2, gap * 2));
        if (preferred.Size.X > 0 && preferred.Size.Y > 0 && bounds.Encloses(preferred) && !preferred.Intersects(characterClearance)
            && (occupied.Size.X <= 0 || occupied.Size.Y <= 0 || !preferred.Intersects(occupiedClearance))) return preferred;
        var free = new List<Rect2I> { bounds };
        Cut(free, characterClearance);
        if (occupied.Size.X > 0 && occupied.Size.Y > 0)
            Cut(free, new(occupied.Position - new Vector2I(gap, gap), occupied.Size + new Vector2I(gap * 2, gap * 2)));
        requested = new(Math.Max(1, requested.X), Math.Max(1, requested.Y));
        double score = double.MaxValue;
        var best = new Rect2I(bounds.Position, Vector2I.Zero);
        foreach (var space in free)
        {
            int width = Math.Min(space.Size.X, requested.X), height = Math.Min(space.Size.Y, requested.Y);
            if (width <= 0 || height <= 0) continue;
            bool left = space.End.X <= character.Position.X;
            bool right = space.Position.X >= character.End.X;
            int desiredX = left ? space.End.X - width : right ? space.Position.X : character.Position.X + (character.Size.X - width) / 2;
            int desiredY = character.Position.Y + character.Size.Y * 16 / 100;
            int x = Math.Clamp(desiredX, space.Position.X, space.End.X - width);
            int y = Math.Clamp(desiredY, space.Position.Y, space.End.Y - height);
            double lost = 1 - (double)width * height / ((double)requested.X * requested.Y);
            double candidate = lost * 1_000_000 + Math.Abs(y - desiredY) + (left ? 0 : right ? 40 : 80);
            if (width < Math.Min(minimum.X, requested.X) || height < Math.Min(minimum.Y, requested.Y)) candidate += 10_000_000;
            if (candidate < score) { score = candidate; best = new(x, y, width, height); }
        }
        return best;
    }

    private static void Cut(List<Rect2I> spaces, Rect2I obstacle)
    {
        var next = new List<Rect2I>();
        foreach (var r in spaces)
        {
            int left = Math.Max(r.Position.X, obstacle.Position.X), top = Math.Max(r.Position.Y, obstacle.Position.Y);
            int right = Math.Min(r.End.X, obstacle.End.X), bottom = Math.Min(r.End.Y, obstacle.End.Y);
            if (left >= right || top >= bottom) { next.Add(r); continue; }
            // Maximal free rectangles may overlap each other; each one is free of every obstacle.
            if (left > r.Position.X) next.Add(new(r.Position.X, r.Position.Y, left - r.Position.X, r.Size.Y));
            if (right < r.End.X) next.Add(new(right, r.Position.Y, r.End.X - right, r.Size.Y));
            if (top > r.Position.Y) next.Add(new(r.Position.X, r.Position.Y, r.Size.X, top - r.Position.Y));
            if (bottom < r.End.Y) next.Add(new(r.Position.X, bottom, r.Size.X, r.End.Y - bottom));
        }
        spaces.Clear(); spaces.AddRange(next);
    }
}
