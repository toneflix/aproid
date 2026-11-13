using System.Text.Json;

namespace Aproid.Plugins;

/// Files that haven't finished moving, kept on disk so a transfer can still resume after FlyyLink quits.
internal sealed class TransferStore(string path)
{
    /// A file we offered to the phone, which it may ask the rest of.
    public sealed record Offered(string Path, string DeviceId, string DeviceName, DateTimeOffset Expires);

    /// A file partly received from the phone.
    public sealed record Partial(string Path, string DeviceId, string DeviceName, long Total, DateTimeOffset Expires);

    private sealed class Contents
    {
        public Dictionary<string, Offered> Offered { get; set; } = [];
        public Dictionary<string, Partial> Partial { get; set; } = [];
    }

    /// How long an unfinished file waits for the other side to come back.
    public static readonly TimeSpan Keep = TimeSpan.FromHours(24);

    private readonly object gate = new();
    private readonly Contents contents = Load(path);

    public IReadOnlyDictionary<string, Offered> OfferedFiles
    {
        get
        {
            lock (gate) return new Dictionary<string, Offered>(contents.Offered);
        }
    }

    public IReadOnlyDictionary<string, Partial> PartialFiles
    {
        get
        {
            lock (gate) return new Dictionary<string, Partial>(contents.Partial);
        }
    }

    public void SetOffered(string id, Offered? value) => Change(c =>
    {
        if (value is null) c.Offered.Remove(id);
        else c.Offered[id] = value;
    });

    public void SetPartial(string id, Partial? value) => Change(c =>
    {
        if (value is null) c.Partial.Remove(id);
        else c.Partial[id] = value;
    });

    /// Drops what has expired and returns the partial files it dropped, so their bytes can be deleted.
    public IReadOnlyList<Partial> RemoveExpired(DateTimeOffset? now = null)
    {
        var at = now ?? DateTimeOffset.Now;
        List<Partial> dropped = [];

        Change(c =>
        {
            foreach (var (id, _) in c.Offered.Where(pair => pair.Value.Expires <= at).ToList()) c.Offered.Remove(id);
            foreach (var (id, partial) in c.Partial.Where(pair => pair.Value.Expires <= at).ToList())
            {
                dropped.Add(partial);
                c.Partial.Remove(id);
            }
        });

        return dropped;
    }

    private void Change(Action<Contents> update)
    {
        string json;
        lock (gate)
        {
            update(contents);
            json = JsonSerializer.Serialize(contents);
        }

        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
            File.WriteAllText(path, json);
        }
        catch (IOException)
        {
        }
    }

    private static Contents Load(string path)
    {
        try
        {
            return JsonSerializer.Deserialize<Contents>(File.ReadAllText(path)) ?? new Contents();
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            return new Contents();
        }
    }
}
