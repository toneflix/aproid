using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Aproid.Core;

/// Finding the phone over Bluetooth when Wi-Fi discovery fails. The phone offers a Bluetooth LE service; a paired
/// computer writes a `Request`, and the phone answers with where to reach it, sealed to that computer's certificate.
/// Mirrors Nearby.kt and Nearby.swift. Only the phone seals answers, so this side only opens them.
public static class Nearby
{
    public static readonly Guid Service = new("a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b40");
    public static readonly Guid RequestCharacteristic = new("a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b41");
    public static readonly Guid AnswerCharacteristic = new("a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b42");

    private const int NonceSize = 12;
    private const int TagSize = 16;

    public enum Want
    {
        /// Just tell me your address.
        Connect,

        /// We share no network: ask the user to turn on your hotspot so I can join it.
        Hotspot,
    }

    public sealed record Request(string DeviceId, Want Want)
    {
        public byte[] Bytes() => Encoding.UTF8.GetBytes(new JsonObject { ["id"] = DeviceId, ["want"] = Want.ToString().ToLowerInvariant() }.ToJsonString());

        public static Request? FromBytes(byte[] bytes)
        {
            try
            {
                if (JsonNode.Parse(bytes) is not JsonObject json || json["id"].AsString() is not string id || !DeviceIdentity.IsValidDeviceId(id)) return null;

                return json["want"].AsString() switch
                {
                    "connect" => new Request(id, Want.Connect),
                    "hotspot" => new Request(id, Want.Hotspot),
                    _ => null,
                };
            }
            catch (JsonException)
            {
                return null;
            }
        }
    }

    /// Where to reach the phone.
    public sealed record Answer(string DeviceId, IReadOnlyList<string> Addresses, int Port)
    {
        public bool Equals(Answer? other) => other is not null && DeviceId == other.DeviceId && Port == other.Port && Addresses.SequenceEqual(other.Addresses);

        public override int GetHashCode() => HashCode.Combine(DeviceId, Port, Addresses.Count);
    }

    /// Reads an answer sealed to our key: an RSA-OAEP (SHA-256) wrapped AES-GCM key, the nonce, then the ciphertext.
    /// Throws when it isn't for our key or was changed on the way.
    public static Answer Open(ReadOnlySpan<byte> sealedBytes, RSA privateKey)
    {
        if (sealedBytes.Length <= 2) throw new ProtocolException("answer too short");

        var wrappedSize = BinaryPrimitives.ReadUInt16BigEndian(sealedBytes);
        var nonceStart = 2 + wrappedSize;
        var cipherStart = nonceStart + NonceSize;
        if (sealedBytes.Length < cipherStart + TagSize) throw new ProtocolException("answer too short");

        var key = privateKey.Decrypt(sealedBytes[2..nonceStart].ToArray(), RSAEncryptionPadding.OaepSHA256);
        var cipher = sealedBytes[cipherStart..^TagSize];
        var plain = new byte[cipher.Length];
        using (var aes = new AesGcm(key, TagSize))
        {
            aes.Decrypt(sealedBytes[nonceStart..cipherStart], cipher, sealedBytes[^TagSize..], plain);
        }

        if (JsonNode.Parse(plain) is not JsonObject json || json["i"].AsString() is not string id || json["p"].AsLong() is not (long port and >= 1 and <= 65535))
            throw new ProtocolException("answer is not valid");

        return new Answer(id, json["a"].AsStringList(), (int)port);
    }
}
