using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.UI;

namespace FlyyLink.Views;

/// Images the phone sends as base64 or files.
internal static class Pictures
{
    /// Decodes a base64 JPEG or PNG, or returns null when there is none. Call on the UI thread.
    public static ImageSource? FromBase64(string? base64, int decodeWidth = 0)
    {
        if (string.IsNullOrEmpty(base64)) return null;

        try
        {
            var bitmap = new BitmapImage { DecodePixelWidth = decodeWidth };
            bitmap.SetSource(new MemoryStream(Convert.FromBase64String(base64)).AsRandomAccessStream());

            return bitmap;
        }
        catch (FormatException)
        {
            return null;
        }
    }

    public static ImageSource? FromFile(string? path, int decodeWidth = 0) =>
        path is not null && File.Exists(path) ? new BitmapImage(new Uri(path)) { DecodePixelWidth = decodeWidth } : null;
}

/// A round contact picture, or coloured initials when there is no photo.
public sealed class Avatar : UserControl
{
    public static readonly DependencyProperty NameTextProperty =
        DependencyProperty.Register(nameof(NameText), typeof(string), typeof(Avatar), new PropertyMetadata("", (d, _) => ((Avatar)d).Draw()));

    public static readonly DependencyProperty PhotoProperty =
        DependencyProperty.Register(nameof(Photo), typeof(string), typeof(Avatar), new PropertyMetadata(null, (d, _) => ((Avatar)d).Draw()));

    public static readonly DependencyProperty DiameterProperty =
        DependencyProperty.Register(nameof(Diameter), typeof(double), typeof(Avatar), new PropertyMetadata(36.0, (d, _) => ((Avatar)d).Draw()));

    private static readonly Color[] Palette =
    [
        Color.FromArgb(255, 0x00, 0x86, 0xC9), Color.FromArgb(255, 0x7C, 0x4D, 0xDB), Color.FromArgb(255, 0xD8, 0x43, 0x8A),
        Color.FromArgb(255, 0xE0, 0x7A, 0x10), Color.FromArgb(255, 0x0F, 0x9D, 0x8F), Color.FromArgb(255, 0x4F, 0x5B, 0xD5),
        Color.FromArgb(255, 0x2E, 0x9E, 0x4F), Color.FromArgb(255, 0xD1, 0x3B, 0x3B),
    ];

    private readonly Microsoft.UI.Xaml.Shapes.Ellipse circle = new();
    private readonly TextBlock initials = new() { Foreground = new SolidColorBrush(Colors.White), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };

    public Avatar()
    {
        IsTabStop = false;
        Content = new Grid { Children = { circle, initials } };
        Draw();
    }

    public string NameText
    {
        get => (string)GetValue(NameTextProperty);
        set => SetValue(NameTextProperty, value);
    }

    public string? Photo
    {
        get => (string?)GetValue(PhotoProperty);
        set => SetValue(PhotoProperty, value);
    }

    public double Diameter
    {
        get => (double)GetValue(DiameterProperty);
        set => SetValue(DiameterProperty, value);
    }

    private void Draw()
    {
        Width = Height = circle.Width = circle.Height = Diameter;
        initials.FontSize = Diameter * 0.38;

        var name = NameText ?? "";
        var picture = Pictures.FromBase64(Photo, (int)(Diameter * 2));
        if (picture is not null)
        {
            circle.Fill = new ImageBrush { ImageSource = picture, Stretch = Stretch.UniformToFill };
            initials.Text = "";
            return;
        }

        var hash = name.Aggregate(0, (sum, c) => (sum * 31 + c) & 0x7fffffff);
        var color = Palette[hash % Palette.Length];
        circle.Fill = new LinearGradientBrush
        {
            StartPoint = new Windows.Foundation.Point(0, 0),
            EndPoint = new Windows.Foundation.Point(0, 1),
            GradientStops =
            {
                new GradientStop { Color = Color.FromArgb(255, (byte)Math.Min(255, color.R + 40), (byte)Math.Min(255, color.G + 40), (byte)Math.Min(255, color.B + 40)), Offset = 0 },
                new GradientStop { Color = color, Offset = 1 },
            },
        };
        initials.Text = Initials(name);
    }

    private static string Initials(string name)
    {
        var words = name.Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(w => char.IsLetter(w[0])).Take(2).ToList();

        return words.Count == 0 ? "#" : string.Concat(words.Select(w => char.ToUpperInvariant(w[0])));
    }
}
