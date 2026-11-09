using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

namespace Aproid.Core;

/// Captures the peer's certificate during a TLS handshake. Every device is self-signed, so the handshake
/// accepts any certificate and the caller checks it afterwards against the device id and the trust store.
internal sealed class PeerCertificate
{
    public byte[]? Der { get; private set; }

    public bool Validate(object sender, X509Certificate? certificate, X509Chain? chain, SslPolicyErrors errors)
    {
        if (certificate is null) return false;

        Der = certificate.GetRawCertData();

        return true;
    }

    public static SslServerAuthenticationOptions ServerOptions(DeviceCertificate own, PeerCertificate peer) => new()
    {
        ServerCertificate = own.Certificate,
        ClientCertificateRequired = true,
        RemoteCertificateValidationCallback = peer.Validate,
        CertificateRevocationCheckMode = X509RevocationMode.NoCheck,
    };

    public static SslClientAuthenticationOptions ClientOptions(DeviceCertificate own, PeerCertificate peer, string targetHost) => new()
    {
        TargetHost = targetHost,
        ClientCertificates = [own.Certificate],
        LocalCertificateSelectionCallback = (_, _, _, _, _) => own.Certificate,
        RemoteCertificateValidationCallback = peer.Validate,
        CertificateRevocationCheckMode = X509RevocationMode.NoCheck,
    };
}
