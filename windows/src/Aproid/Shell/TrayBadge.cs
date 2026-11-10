using System.Drawing;
using System.Drawing.Drawing2D;
using Aproid.Core;

namespace Aproid.Shell;

/// Draws the tray icon with the phone's battery as a bar along its bottom edge.
internal sealed class TrayBadge(string iconPath)
{
    private static readonly Color Track = Color.FromArgb(150, 0, 0, 0);
    private static readonly Color Full = Color.FromArgb(255, 52, 199, 89);
    private static readonly Color Charging = Color.FromArgb(255, 10, 132, 255);
    private static readonly Color Low = Color.FromArgb(255, 255, 159, 10);

    /// A new icon handle at `size` pixels, which the caller destroys. Without a battery it is the plain icon.
    public IntPtr Draw(int size, BatteryStatus? battery)
    {
        using var source = new Icon(iconPath, size, size);
        using var bitmap = new Bitmap(size, size);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.DrawIcon(source, new Rectangle(0, 0, size, size));

            if (battery is not null) DrawBar(graphics, size, battery);
        }

        return bitmap.GetHicon();
    }

    private static void DrawBar(Graphics graphics, int size, BatteryStatus battery)
    {
        var height = Math.Max(2, size / 7);
        var top = size - height;
        var filled = (int)Math.Round(size * Math.Clamp(battery.Charge, 0, 100) / 100.0);
        var color = battery.IsCharging ? Charging : battery.IsLow ? Low : Full;

        using var track = new SolidBrush(Track);
        using var fill = new SolidBrush(color);
        graphics.FillRectangle(track, 0, top, size, height);
        graphics.FillRectangle(fill, 0, top, Math.Max(filled, 1), height);
    }
}
