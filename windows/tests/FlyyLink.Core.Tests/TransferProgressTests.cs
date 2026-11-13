using FlyyLink.Core;

namespace FlyyLink.Core.Tests;

public class TransferProgressTests
{
    private sealed class Clock
    {
        public long Nanos { get; set; }
    }

    [Fact]
    public void ReportsAboutTenTimesASecond()
    {
        var clock = new Clock();
        var progress = new TransferProgress(1000, clock: () => clock.Nanos);

        Assert.Null(progress.Advance(10));

        clock.Nanos += 100_000_000;
        Assert.Equal(20, progress.Advance(10)!.Done);
    }

    [Fact]
    public void SpeedAndTimeLeftWaitForTheFirstSecond()
    {
        var clock = new Clock();
        var progress = new TransferProgress(1000, alreadyDone: 200, clock: () => clock.Nanos);

        clock.Nanos += 500_000_000;
        Assert.Null(progress.Advance(100)!.BytesPerSecond);

        clock.Nanos += 500_000_000;
        var reading = progress.Advance(100)!;
        Assert.Equal(200, reading.BytesPerSecond);
        Assert.Equal(3, reading.SecondsLeft);
        Assert.Equal(0.4, reading.Fraction, 3);
    }

    [Fact]
    public void FinishingAlwaysReports()
    {
        var progress = new TransferProgress(10);

        Assert.Equal(1.0, progress.Advance(10)!.Fraction);
    }
}
