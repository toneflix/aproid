using System.Diagnostics;

namespace Aproid.Core;

/// Tracks how far a file transfer has got, how fast it is moving and how long is left.
/// Safe to advance from a background thread and read from the UI. Mirrors TransferProgress.kt and .swift.
public sealed class TransferProgress
{
    /// One reading, safe to hand to the UI.
    public sealed record Snapshot(long Done, long Total, long? BytesPerSecond, long? SecondsLeft)
    {
        public double Fraction => Total <= 0 ? 1 : Math.Clamp((double)Done / Total, 0, 1);
    }

    private const long ReportEveryNanos = 100_000_000;

    /// Speed reads wildly in the first moments, so it is held back until then.
    private const double MinSeconds = 1.0;

    private readonly Func<long> clock;
    private readonly long startedAt;
    private readonly long startedWith;
    private readonly object gate = new();
    private long done;
    private long reportedAt;

    public TransferProgress(long total, long alreadyDone = 0, Func<long>? clock = null)
    {
        Total = total;
        this.clock = clock ?? (() => (long)(Stopwatch.GetTimestamp() * (1e9 / Stopwatch.Frequency)));
        startedAt = this.clock();
        startedWith = Math.Min(Math.Max(alreadyDone, 0), Math.Max(total, 0));
        done = startedWith;
        reportedAt = startedAt;
    }

    public long Total { get; }

    /// Adds `bytes` and returns a reading when the UI is due one, about ten times a second.
    public Snapshot? Advance(long bytes)
    {
        lock (gate)
        {
            done = Math.Min(done + bytes, Total);
            var now = clock();
            if (now - reportedAt < ReportEveryNanos && done < Total) return null;

            reportedAt = now;

            return SnapshotAt(now);
        }
    }

    public Snapshot Read()
    {
        lock (gate) return SnapshotAt(clock());
    }

    private Snapshot SnapshotAt(long now)
    {
        var seconds = (now - startedAt) / 1e9;
        var moved = done - startedWith;
        long? speed = seconds >= MinSeconds && moved > 0 ? Math.Max((long)(moved / seconds), 1) : null;
        long? left = speed is long s ? (long)Math.Ceiling((double)(Total - done) / s) : null;

        return new Snapshot(done, Total, speed, left);
    }
}
