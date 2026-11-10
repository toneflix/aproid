using Aproid.Core;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace Aproid.Plugins;

/// Plays the phone's sound while mirroring. The stream carries 16-bit PCM, which goes straight to the
/// output with only a small buffer, so the sound stays close to the picture. Frames arrive on a network thread.
internal sealed class ScreenAudio : IDisposable
{
    /// More sound than this waiting means it has fallen behind, so new pieces are dropped.
    private static readonly TimeSpan MaxQueued = TimeSpan.FromMilliseconds(160);

    private const int OutputLatencyMs = 60;

    private readonly object gate = new();
    private WasapiOut? output;
    private BufferedWaveProvider? buffer;
    private bool muted;

    public bool IsMuted
    {
        get
        {
            lock (gate) return muted;
        }
        set
        {
            lock (gate)
            {
                muted = value;
                if (output is not null) output.Volume = muted ? 0 : 1;
            }
        }
    }

    /// Gets ready for a stream with this sound format.
    public void Start(long rate, long channels)
    {
        lock (gate)
        {
            StopLocked();

            buffer = new BufferedWaveProvider(new WaveFormat((int)rate, 16, (int)channels))
            {
                BufferDuration = MaxQueued,
                DiscardOnBufferOverflow = true,
                ReadFully = true,
            };

            try
            {
                output = new WasapiOut(AudioClientShareMode.Shared, true, OutputLatencyMs);
                output.Init(buffer);
                output.Volume = muted ? 0 : 1;
                output.Play();
            }
            catch (Exception e) when (e is not OutOfMemoryException)
            {
                System.Diagnostics.Debug.WriteLine($"Could not start sound: {e.Message}");
                StopLocked();
            }
        }
    }

    public void Stop()
    {
        lock (gate) StopLocked();
    }

    /// Queues one piece of interleaved little-endian 16-bit sound.
    public void Play(ScreenFrame frame)
    {
        lock (gate) buffer?.AddSamples(frame.Data, 0, frame.Data.Length);
    }

    public void Dispose() => Stop();

    private void StopLocked()
    {
        output?.Stop();
        output?.Dispose();
        output = null;
        buffer = null;
    }
}
