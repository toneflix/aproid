using Aproid.Core;

namespace Aproid.Model;

public enum MirrorPhase
{
    Idle,
    Waiting,
    Live,
    Ended,
}

/// The state of mirroring the phone's screen, for the screen window. Use on the UI thread.
public sealed class ScreenMirror : Observable
{
    private MirrorPhase phase;
    private string deviceName = "";
    private (long Width, long Height) size;
    private bool isMuted;

    /// Sends a packet to a phone. Set by the app model.
    internal Func<string, NetworkPacket, bool>? Send { get; set; }

    public string? DeviceId { get; private set; }

    public MirrorPhase Phase
    {
        get => phase;
        private set => Set(ref phase, value);
    }

    public string DeviceName
    {
        get => deviceName;
        private set => Set(ref deviceName, value);
    }

    /// The picture's size in pixels, once the phone said it.
    public (long Width, long Height) Size
    {
        get => size;
        private set => Set(ref size, value);
    }

    /// Silences the phone's sound on this PC.
    public bool IsMuted
    {
        get => isMuted;
        set => Set(ref isMuted, value);
    }

    /// Asks the phone to start; it shows a prompt the user has to allow.
    public void Begin(string id, string name)
    {
        if (Phase == MirrorPhase.Live && DeviceId == id) return;

        if (DeviceId is string old && old != id) Send?.Invoke(old, Screen.Stop());
        DeviceId = id;
        DeviceName = name;
        Phase = Send?.Invoke(id, Screen.Start(audio: true)) == true ? MirrorPhase.Waiting : MirrorPhase.Ended;
    }

    public void Stop()
    {
        if (DeviceId is not string id) return;

        Send?.Invoke(id, Screen.Stop());
        DeviceId = null;
        Phase = MirrorPhase.Idle;
    }

    public void Input(ScreenInput input)
    {
        if (Phase == MirrorPhase.Live && DeviceId is string id) Send?.Invoke(id, input.ToPacket());
    }

    /// A stream arrived, whether this PC asked for it or the user started it on the phone.
    public void Started(string id, string name, long width, long height)
    {
        if (DeviceId is string old && old != id) Send?.Invoke(old, Screen.Stop());

        DeviceId = id;
        DeviceName = name;
        Size = (width, height);
        Phase = MirrorPhase.Live;
    }

    public void Ended(string id)
    {
        if (id == DeviceId && Phase != MirrorPhase.Idle) Phase = MirrorPhase.Ended;
    }
}
