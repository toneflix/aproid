using System.Text.Json;

namespace Aproid.Core;

/// Certificates of paired devices, by device id.
public interface ITrustStore
{
    byte[]? Certificate(string deviceId);

    void Trust(string deviceId, byte[] certificate);

    void Forget(string deviceId);

    bool IsTrusted(string deviceId) => Certificate(deviceId) is not null;
}

public sealed class InMemoryTrustStore : ITrustStore
{
    private readonly Dictionary<string, byte[]> certificates = [];
    private readonly object gate = new();

    public byte[]? Certificate(string deviceId)
    {
        lock (gate) return certificates.GetValueOrDefault(deviceId);
    }

    public void Trust(string deviceId, byte[] certificate)
    {
        lock (gate) certificates[deviceId] = certificate;
    }

    public void Forget(string deviceId)
    {
        lock (gate) certificates.Remove(deviceId);
    }
}

/// Keeps trusted certificates in a JSON file, as base64 DER by device id.
public sealed class FileTrustStore(string path) : ITrustStore
{
    private readonly object gate = new();
    private Dictionary<string, string>? certificates;

    /// Every device we have paired with.
    public IReadOnlyList<string> TrustedIds
    {
        get
        {
            lock (gate) return [.. Load().Keys];
        }
    }

    public byte[]? Certificate(string deviceId)
    {
        lock (gate) return Load().TryGetValue(deviceId, out var der) ? Convert.FromBase64String(der) : null;
    }

    public void Trust(string deviceId, byte[] certificate) => Change(all => all[deviceId] = Convert.ToBase64String(certificate));

    public void Forget(string deviceId) => Change(all => all.Remove(deviceId));

    private void Change(Action<Dictionary<string, string>> update)
    {
        lock (gate)
        {
            var all = Load();
            update(all);

            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, JsonSerializer.Serialize(all));
        }
    }

    private Dictionary<string, string> Load()
    {
        if (certificates is not null) return certificates;

        try
        {
            certificates = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path)) ?? [];
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            certificates = [];
        }

        return certificates;
    }
}
