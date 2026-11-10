using Aproid.Core;
using Windows.Media.Control;

namespace Aproid.Shell;

/// The media sessions Windows shows in its volume flyout, read and controlled so paired computers can show them.
internal sealed class LocalMedia
{
    private readonly HashSet<string> watched = [];
    private GlobalSystemMediaTransportControlsSessionManager? manager;

    /// Called on a background thread when a session starts, stops or changes track.
    public Action? OnChange { get; set; }

    public async Task StartAsync()
    {
        try
        {
            manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        }
        catch (Exception e)
        {
            System.Diagnostics.Debug.WriteLine($"Media sessions unavailable: {e.Message}");
            return;
        }

        manager.SessionsChanged += (_, _) =>
        {
            lock (watched) watched.Clear();
            Watch();
            OnChange?.Invoke();
        };
        Watch();
    }

    public async Task<IReadOnlyList<MediaPlayer>> PlayersAsync()
    {
        var players = new List<MediaPlayer>();
        foreach (var session in Sessions())
        {
            if (await ReadAsync(session) is MediaPlayer player && players.All(p => p.Name != player.Name)) players.Add(player);
        }

        return players;
    }

    public async Task PerformAsync(MediaRequest request)
    {
        if (Sessions().FirstOrDefault(s => NameOf(s) == request.Player) is not { } session) return;

        try
        {
            if (request.Action is MediaAction action)
            {
                await (action switch
                {
                    MediaAction.Play => session.TryPlayAsync(),
                    MediaAction.Pause => session.TryPauseAsync(),
                    MediaAction.Next => session.TrySkipNextAsync(),
                    MediaAction.Previous => session.TrySkipPreviousAsync(),
                    MediaAction.Stop => session.TryStopAsync(),
                    _ => session.TryTogglePlayPauseAsync(),
                });
            }

            if (request.SeekTo is long position) await session.TryChangePlaybackPositionAsync(TimeSpan.FromMilliseconds(position).Ticks);
        }
        catch (Exception e)
        {
            System.Diagnostics.Debug.WriteLine($"Media control failed: {e.Message}");
        }
    }


    private IReadOnlyList<GlobalSystemMediaTransportControlsSession> Sessions() => manager?.GetSessions().ToList() ?? [];

    /// Listens to each session once, so a new track or play state reaches paired devices.
    private void Watch()
    {
        foreach (var session in Sessions())
        {
            lock (watched)
            {
                if (!watched.Add(session.SourceAppUserModelId)) continue;
            }

            session.MediaPropertiesChanged += (_, _) => OnChange?.Invoke();
            session.PlaybackInfoChanged += (_, _) => OnChange?.Invoke();
        }
    }

    private static async Task<MediaPlayer?> ReadAsync(GlobalSystemMediaTransportControlsSession session)
    {
        try
        {
            var properties = await session.TryGetMediaPropertiesAsync();
            var playback = session.GetPlaybackInfo();
            var timeline = session.GetTimelineProperties();
            var controls = playback.Controls;
            var length = (long)(timeline.EndTime - timeline.StartTime).TotalMilliseconds;

            return new MediaPlayer(NameOf(session))
            {
                Title = properties.Title ?? "",
                Artist = properties.Artist ?? "",
                Album = properties.AlbumTitle ?? "",
                IsPlaying = playback.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
                Position = Math.Max(0, (long)(timeline.Position - timeline.StartTime).TotalMilliseconds),
                Length = Math.Max(0, length),
                CanPlay = controls.IsPlayEnabled,
                CanPause = controls.IsPauseEnabled,
                CanGoNext = controls.IsNextEnabled,
                CanGoPrevious = controls.IsPreviousEnabled,
                CanSeek = controls.IsPlaybackPositionEnabled && length > 0,
            };
        }
        catch (Exception e)
        {
            System.Diagnostics.Debug.WriteLine($"Could not read a media session: {e.Message}");
            return null;
        }
    }

    /// A short app name from the session's app id, such as "Spotify" from "Spotify.exe".
    private static string NameOf(GlobalSystemMediaTransportControlsSession session)
    {
        var id = session.SourceAppUserModelId;
        var name = id.Split('!')[0].Split('_')[0];
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name[..^4];

        name = name.Split('.').LastOrDefault(part => part.Length > 0) ?? name;

        return name.Length > 0 ? name : "Media";
    }
}
