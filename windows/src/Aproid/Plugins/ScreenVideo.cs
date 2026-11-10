using System.Runtime.InteropServices.WindowsRuntime;
using Aproid.Core;
using Windows.Media.Core;
using Windows.Media.MediaProperties;

namespace Aproid.Plugins;

/// Feeds the phone's H.264 frames to Windows' decoder as a live media source. Frames arrive on a network thread.
internal sealed class ScreenVideo
{
    /// When the decoder falls this far behind, older pictures are dropped up to the next key frame.
    private const int MaxQueued = 20;

    private readonly object gate = new();
    private readonly Queue<ScreenFrame> frames = new();
    private MediaStreamSourceSampleRequest? waiting;
    private MediaStreamSourceSampleRequestDeferral? deferral;
    private byte[]? config;
    private long? firstUs;
    private bool seenKey;

    /// Forgets the last stream. Call before the new stream's first frame arrives.
    public void Reset()
    {
        lock (gate)
        {
            frames.Clear();
            Release();
            config = null;
            firstUs = null;
            seenKey = false;
        }
    }

    /// A source for the decoder that plays the current stream, which is this size.
    public MediaStreamSource CreateSource(uint width, uint height)
    {
        var properties = VideoEncodingProperties.CreateH264();
        if (width > 0 && height > 0)
        {
            properties.Width = width;
            properties.Height = height;
        }

        var source = new MediaStreamSource(new VideoStreamDescriptor(properties))
        {
            BufferTime = TimeSpan.Zero,
            IsLive = true,
            CanSeek = false,
        };
        source.Starting += (_, args) => args.Request.SetActualStartPosition(TimeSpan.Zero);
        source.SampleRequested += SampleRequested;
        source.Closed += (_, _) =>
        {
            lock (gate) Release();
        };

        return source;
    }

    public void Push(ScreenFrame frame)
    {
        // This app doesn't ask for sound, but a phone could still send it.
        if (frame.IsAudio) return;

        lock (gate)
        {
            if (frame.IsConfig)
            {
                config = frame.Data;
                return;
            }

            // Pictures before the first key frame can't be decoded.
            if (!seenKey && !frame.IsKey) return;

            seenKey = true;
            if (waiting is not null)
            {
                waiting.Sample = Sample(frame);
                Release();
                return;
            }

            frames.Enqueue(frame);
            if (frames.Count > MaxQueued && frame.IsKey)
            {
                while (frames.Count > 1) frames.Dequeue();
            }
        }
    }

    private void SampleRequested(MediaStreamSource sender, MediaStreamSourceSampleRequestedEventArgs args)
    {
        lock (gate)
        {
            if (frames.TryDequeue(out var frame))
            {
                args.Request.Sample = Sample(frame);
                return;
            }

            waiting = args.Request;
            deferral = args.Request.GetDeferral();
        }
    }

    /// The decoder needs the SPS and PPS in front of each key frame.
    private MediaStreamSample Sample(ScreenFrame frame)
    {
        var data = frame.IsKey && config is not null ? [.. config, .. frame.Data] : frame.Data;
        firstUs ??= frame.TimeUs;

        var sample = MediaStreamSample.CreateFromBuffer(data.AsBuffer(), TimeSpan.FromTicks(Math.Max(0, frame.TimeUs - firstUs.Value) * 10));
        sample.KeyFrame = frame.IsKey;

        return sample;
    }

    private void Release()
    {
        deferral?.Complete();
        deferral = null;
        waiting = null;
    }
}
