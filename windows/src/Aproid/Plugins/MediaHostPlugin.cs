using Aproid.Core;
using Aproid.Model;
using Aproid.Shell;

namespace Aproid.Plugins;

/// Lets paired devices see and control what this PC is playing ("kdeconnect.mpris.request").
internal sealed class MediaHostPlugin : IPlugin
{
    private readonly DeviceRegistry devices;
    private readonly LocalMedia media = new();
    private readonly SemaphoreSlim gate = new(1, 1);
    private IReadOnlyList<MediaPlayer> lastSent = [];

    public MediaHostPlugin(DeviceRegistry devices)
    {
        this.devices = devices;

        media.OnChange = () => _ = BroadcastAsync();
        _ = media.StartAsync();
    }

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.MprisRequest };

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (MediaRequest.FromPacket(packet) is MediaRequest request) _ = AnswerAsync(request, device);
    }

    private async Task AnswerAsync(MediaRequest request, Device device)
    {
        var changes = request.Action is not null || request.SeekTo is not null;
        if (changes) await media.PerformAsync(request);

        var players = await media.PlayersAsync();
        if (request.WantsPlayerList) device.Send(Media.PlayerListPacket(players.Select(p => p.Name)));
        if ((request.WantsNowPlaying || changes) && players.FirstOrDefault(p => p.Name == request.Player) is MediaPlayer player) device.Send(player.ToPacket());
    }

    /// Tells every paired device about a change, once per change.
    private async Task BroadcastAsync()
    {
        await gate.WaitAsync();
        try
        {
            var players = await media.PlayersAsync();
            if (players.SequenceEqual(lastSent)) return;

            var namesChanged = !players.Select(p => p.Name).SequenceEqual(lastSent.Select(p => p.Name));
            lastSent = players;

            foreach (var device in devices.Paired.Where(d => d.Link.Identity.IncomingCapabilities.Contains(PacketType.Mpris)))
            {
                if (namesChanged) device.Send(Media.PlayerListPacket(players.Select(p => p.Name)));
                foreach (var player in players) device.Send(player.ToPacket());
            }
        }
        finally
        {
            gate.Release();
        }
    }
}
