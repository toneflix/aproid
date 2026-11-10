using Aproid.Core;

namespace Aproid.Core.Tests;

/// Mirrors ScreenTests.swift and the Kotlin screen tests.
public class ScreenTests
{
    private static NetworkPacket Wire(NetworkPacket packet) => NetworkPacket.Parse(packet.Serialize());

    [Fact]
    public void RequestsRoundTripWithinLimits()
    {
        Assert.Equal(new Screen.Request(Screen.Action.Start, 1280, 4_000_000), Screen.RequestOf(Wire(Screen.Start(1280, 4_000_000))));
        Assert.Equal(new Screen.Request(Screen.Action.Start, 4096, 50_000_000), Screen.RequestOf(Wire(Screen.Start(99_999, 900_000_000))));
        Assert.Equal(Screen.Action.Stop, Screen.RequestOf(Wire(Screen.Stop()))?.Action);
        Assert.Equal(new Screen.Info(1080, 2400, true), Screen.InfoOf(Wire(Screen.Started(1080, 2400))));
        Assert.False(Screen.InfoOf(Wire(Screen.Stopped()))?.Running);
    }

    [Fact]
    public void SoundIsAskedForAndAnnounced()
    {
        Assert.False(Screen.RequestOf(Wire(Screen.Start()))?.Audio);
        Assert.True(Screen.RequestOf(Wire(Screen.Start(audio: true)))?.Audio);
        Assert.False(Screen.InfoOf(Wire(Screen.Started(1080, 2400)))?.HasAudio);

        var info = Screen.InfoOf(Wire(Screen.Started(1080, 2400, audio: true)));
        Assert.Equal(new Screen.Info(1080, 2400, true, Screen.AudioRate, Screen.AudioChannels), info);
        Assert.True(info!.HasAudio);
    }

    [Fact]
    public void InputRoundTripsAndRejectsNonsense()
    {
        ScreenInput[] inputs =
        [
            new ScreenInput.Tap(0.5, 0.25),
            new ScreenInput.LongPress(0, 1),
            new ScreenInput.Swipe(0.5, 0.8, 0.5, 0.2, 300),
            new ScreenInput.Text("hello"),
            new ScreenInput.KeyPress(ScreenInput.Back),
        ];

        foreach (var input in inputs) Assert.Equal(input, ScreenInput.FromPacket(Wire(input.ToPacket())));
        Assert.Null(ScreenInput.FromPacket(Wire(new ScreenInput.Tap(1.5, 0.2).ToPacket())));
        Assert.Null(ScreenInput.FromPacket(Wire(new ScreenInput.KeyPress("reboot").ToPacket())));
    }

    [Fact]
    public void ReaderRebuildsFramesSplitAnywhere()
    {
        ScreenFrame[] frames =
        [
            new([0, 0, 0, 1, 0x67], 0, ScreenFrame.Config),
            new(Enumerable.Range(0, 5000).Select(i => (byte)(i % 256)).ToArray(), 33_333, ScreenFrame.Key),
            new([9, 9], 50_000, 0),
            new(Enumerable.Range(0, 3840).Select(i => (byte)(i * 3 % 256)).ToArray(), 60_000, ScreenFrame.Audio),
        ];
        var stream = frames.SelectMany(f => f.Header().Concat(f.Data)).ToArray();
        var reader = new ScreenFrameReader();

        var read = new List<ScreenFrame>();
        for (var start = 0; start < stream.Length; start += 7) read.AddRange(reader.Feed(stream.AsSpan(start, Math.Min(7, stream.Length - start))));

        Assert.Equal(frames, read);
        Assert.True(read[0].IsConfig && read[1].IsKey && read[3].IsAudio && !read[1].IsAudio);
    }

    [Fact]
    public void HeaderMatchesTheKotlinLayout()
    {
        var header = new ScreenFrame(new byte[258], 1, ScreenFrame.Key).Header();

        Assert.Equal([0, 0, 1, 2, 0, 0, 0, 0, 0, 0, 0, 1, 2], header);
    }
}
