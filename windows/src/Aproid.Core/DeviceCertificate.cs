using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace Aproid.Core;

/// This device's self-signed certificate. The common name is the device id,
/// which is how KDE Connect ties a TLS session to an identity.
public sealed class DeviceCertificate
{
    /// The certificate with its private key, loaded so the Windows TLS stack can use it.
    public X509Certificate2 Certificate { get; }

    public byte[] CertificateDer { get; }

    /// SubjectPublicKeyInfo bytes, used for the verification code.
    public byte[] PublicKeyDer { get; }

    private DeviceCertificate(X509Certificate2 certificate)
    {
        if (!certificate.HasPrivateKey) throw new ProtocolException("certificate has no private key");

        Certificate = certificate;
        CertificateDer = certificate.RawData;
        PublicKeyDer = certificate.PublicKey.ExportSubjectPublicKeyInfo();
    }

    public string? DeviceId => CommonName(CertificateDer);

    /// The certificate and key as PKCS#12, for storage.
    public byte[] ExportPfx() => Certificate.Export(X509ContentType.Pkcs12);

    public static DeviceCertificate FromPfx(byte[] pfx) =>
        new(new X509Certificate2(pfx, (string?)null, X509KeyStorageFlags.Exportable | X509KeyStorageFlags.UserKeySet));

    public static DeviceCertificate Generate(string deviceId, DateTimeOffset? now = null)
    {
        var at = now ?? DateTimeOffset.UtcNow;
        using var key = RSA.Create(2048);

        var name = new X500DistinguishedNameBuilder();
        name.AddCommonName(deviceId);
        name.AddOrganizationName("KDE");
        name.AddOrganizationalUnitName("KDE Connect");

        var request = new CertificateRequest(name.Build(), key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var created = request.CreateSelfSigned(at.AddDays(-1), at.AddDays(3650));

        // A freshly created key is ephemeral, which Windows TLS refuses. A PKCS#12 round trip stores it properly.
        return FromPfx(created.Export(X509ContentType.Pkcs12));
    }

    public static string? CommonName(byte[] der)
    {
        try
        {
            using var certificate = new X509Certificate2(der);
            var name = certificate.GetNameInfo(X509NameType.SimpleName, forIssuer: false);

            return string.IsNullOrEmpty(name) ? null : name;
        }
        catch (CryptographicException)
        {
            return null;
        }
    }

    public static byte[] PublicKeyOf(X509Certificate2 certificate) => certificate.PublicKey.ExportSubjectPublicKeyInfo();
}

/// The short code both screens show while pairing. It is a SHA-256 over both public keys
/// (larger first, compared as unsigned bytes) and the pair request timestamp, cut to 8 hex characters.
/// Mirrors VerificationKey.kt and VerificationKey in Swift.
public static class VerificationKey
{
    public static string Compute(byte[] publicKeyA, byte[] publicKeyB, long timestamp)
    {
        var aFirst = publicKeyA.AsSpan().SequenceCompareTo(publicKeyB) >= 0;
        var (first, second) = aFirst ? (publicKeyA, publicKeyB) : (publicKeyB, publicKeyA);

        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        hash.AppendData(first);
        hash.AppendData(second);
        hash.AppendData(System.Text.Encoding.UTF8.GetBytes(timestamp.ToString(System.Globalization.CultureInfo.InvariantCulture)));

        return Convert.ToHexString(hash.GetHashAndReset())[..8].ToUpperInvariant();
    }
}
