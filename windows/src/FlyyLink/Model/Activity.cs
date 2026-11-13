using FlyyLink.Core;
using FlyyLink.Icons;

namespace FlyyLink.Model;

public enum ActivityKind
{
    Receiving,
    Received,
    Sending,
    Sent,
    Failed,
    Link,
    Text,
}

/// One line in the panel's Recent list. `Path` is the received file, `Url` the opened link.
public sealed record Activity(ActivityKind Kind, string Title, string Detail)
{
    public Guid Id { get; init; } = Guid.NewGuid();

    public DateTimeOffset Date { get; init; } = DateTimeOffset.Now;

    public TransferProgress.Snapshot? Progress { get; init; }

    public string? Path { get; init; }

    public string? Url { get; init; }

    public bool IsInProgress => Kind is ActivityKind.Receiving or ActivityKind.Sending;

    public bool ShowsProgress => Progress is not null;

    /// The row's tooltip: what clicking it does.
    public string? Hint => Path is not null ? "Click to open · right-click to show in folder" : Url is not null ? "Click to open" : null;

    public double ProgressPercent => (Progress?.Fraction ?? 0) * 100;

    /// The detail line, or how far the transfer has got while it moves.
    public string Caption => Progress is { } progress ? Bytes.ProgressText(progress) : Detail;

    public Lucide Icon => Kind switch
    {
        ActivityKind.Link => Lucide.Link,
        ActivityKind.Text => Lucide.Clipboard,
        ActivityKind.Failed => Lucide.TriangleAlert,
        _ => FileIcon(Title),
    };

    private static Lucide FileIcon(string name) => System.IO.Path.GetExtension(name).ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" or ".png" or ".gif" or ".heic" or ".webp" or ".bmp" => Lucide.Image,
        ".mp4" or ".mov" or ".mkv" or ".avi" or ".webm" or ".3gp" => Lucide.Film,
        ".mp3" or ".m4a" or ".wav" or ".flac" or ".ogg" or ".aac" or ".opus" => Lucide.AudioLines,
        ".pdf" or ".txt" or ".doc" or ".docx" => Lucide.FileText,
        ".zip" or ".rar" or ".7z" or ".tar" or ".gz" or ".apk" => Lucide.FileArchive,
        _ => Lucide.File,
    };
}

/// Byte counts the way Explorer shows them.
public static class Bytes
{
    private static readonly string[] Units = ["bytes", "KB", "MB", "GB", "TB"];

    public static string Text(long count)
    {
        double value = count;
        var unit = 0;
        while (value >= 1000 && unit < Units.Length - 1)
        {
            value /= 1000;
            unit++;
        }

        return unit == 0 ? $"{count} bytes" : $"{value:0.#} {Units[unit]}";
    }

    /// "120 MB of 1.2 GB · 41 MB/s · 28 s left"
    public static string ProgressText(TransferProgress.Snapshot reading)
    {
        var parts = new List<string> { $"{Text(reading.Done)} of {Text(reading.Total)}" };
        if (reading.BytesPerSecond is long speed) parts.Add($"{Text(speed)}/s");
        if (reading.SecondsLeft is long left) parts.Add(TimeLeft(left));

        return string.Join(" · ", parts);
    }

    private static string TimeLeft(long seconds)
    {
        if (seconds < 60) return $"{Math.Max(seconds, 1)} s left";

        var time = TimeSpan.FromSeconds(seconds);

        return time.TotalHours >= 1 ? $"{(int)time.TotalHours} h {time.Minutes} min left" : $"{time.Minutes} min left";
    }
}

/// "2 min ago" style times.
public static class RelativeTime
{
    public static string Text(DateTimeOffset date, DateTimeOffset? now = null)
    {
        var elapsed = (now ?? DateTimeOffset.Now) - date;

        if (elapsed.TotalSeconds < 45) return "just now";
        if (elapsed.TotalMinutes < 60) return $"{Math.Max(1, (int)Math.Round(elapsed.TotalMinutes))} min ago";
        if (elapsed.TotalHours < 24) return $"{(int)elapsed.TotalHours} hr ago";

        return $"{(int)elapsed.TotalDays} d ago";
    }
}
