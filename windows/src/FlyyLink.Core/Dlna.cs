using System.Globalization;
using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace FlyyLink.Core;

/// SSDP, the multicast search that finds TVs and speakers able to play media sent over DLNA.
/// Mirrors Dlna.kt and Dlna.swift.
public static class Ssdp
{
    public const string Address = "239.255.255.250";
    public const int Port = 1900;
    public const string Renderer = "urn:schemas-upnp-org:device:MediaRenderer:1";

    public static string SearchMessage(string target = Renderer, int waitSeconds = 2) =>
        "M-SEARCH * HTTP/1.1\r\n" +
        $"HOST: {Address}:{Port}\r\n" +
        "MAN: \"ssdp:discover\"\r\n" +
        $"MX: {waitSeconds}\r\n" +
        $"ST: {target}\r\n" +
        "\r\n";

    /// Null unless the message is a search answer or an alive notice with a description location.
    public static SsdpReply? Parse(string message)
    {
        var lines = message.Replace("\r\n", "\n").Split('\n');
        var start = lines[0].ToUpperInvariant();
        if (!start.StartsWith("HTTP/1.1 200") && !start.StartsWith("NOTIFY")) return null;

        var headers = HttpHeaders.Parse(lines.Skip(1), upper: true);
        if (headers.GetValueOrDefault("NTS") == "ssdp:byebye") return null;

        if (headers.GetValueOrDefault("LOCATION") is not string location || !location.StartsWith("http")) return null;

        return new SsdpReply(location, headers.GetValueOrDefault("USN") ?? "", headers.GetValueOrDefault("ST") ?? headers.GetValueOrDefault("NT") ?? "");
    }
}

public sealed record SsdpReply(string Location, string Usn, string Target);

/// A TV or speaker that plays media from a URL: a DLNA one as its UPnP device description lists it, or a Google Cast one.
public sealed record TvRenderer(string Id, string Name, string AvTransportUrl = "", string? RenderingControlUrl = null, CastEndpoint? Cast = null)
{
    /// The address of the TV, used to pick the local address it can reach us on.
    public string Host => Cast?.Host ?? new Uri(AvTransportUrl).Host;

    /// Reads the first device that has an AVTransport service, resolving its URLs against the location.
    public static TvRenderer? Parse(string xml, string location)
    {
        if (Xml.Parse(xml) is not XElement root) return null;

        var urlBase = Xml.Text(root, "URLBase") ?? location;

        foreach (var device in Xml.Descendants(root, "device"))
        {
            var services = Xml.Child(device, "serviceList") is XElement list ? Xml.Children(list, "service").ToList() : [];
            if (ControlUrl(services, AvTransport.ServicePrefix) is not string transport) continue;

            return new TvRenderer(
                Xml.Text(device, "UDN") ?? location,
                Xml.Text(device, "friendlyName") ?? new Uri(location).Host,
                Resolve(urlBase, transport),
                ControlUrl(services, RenderingControl.ServicePrefix) is string rendering ? Resolve(urlBase, rendering) : null);
        }

        return null;
    }

    private static string? ControlUrl(List<XElement> services, string typePrefix) =>
        services.FirstOrDefault(s => Xml.Text(s, "serviceType")?.StartsWith(typePrefix) == true) is XElement service
            ? Xml.Text(service, "controlURL")
            : null;

    private static string Resolve(string urlBase, string url) =>
        Uri.TryCreate(new Uri(urlBase), url.Trim(), out var resolved) ? resolved.ToString() : url;
}

/// What kind of media a file is, which picks how a TV shows it.
public enum CastKind
{
    Photo,
    Video,
    Music,
}

public static class CastKinds
{
    public static string UpnpClass(this CastKind kind) => kind switch
    {
        CastKind.Photo => "object.item.imageItem.photo",
        CastKind.Video => "object.item.videoItem",
        _ => "object.item.audioItem.musicTrack",
    };

    /// Null for anything a TV can't play, such as a document.
    public static CastKind? Of(string? mime) => mime?.Split('/')[0].ToLowerInvariant() switch
    {
        "image" => CastKind.Photo,
        "video" => CastKind.Video,
        "audio" => CastKind.Music,
        _ => null,
    };
}

/// One UPnP action, sent as a SOAP request to a service's control URL.
public sealed record SoapCall(string Service, string Action, IReadOnlyList<KeyValuePair<string, string>> Arguments)
{
    public string SoapAction => $"\"{Service}#{Action}\"";

    public string? Argument(string name) => Arguments.FirstOrDefault(a => a.Key == name).Value;

    public string Envelope()
    {
        var body = string.Concat(Arguments.Select(a => $"<{a.Key}>{Xml.Escape(a.Value)}</{a.Key}>"));

        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
            "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">" +
            $"<s:Body><u:{Action} xmlns:u=\"{Service}\">{body}</u:{Action}></s:Body></s:Envelope>";
    }

    public bool Equals(SoapCall? other) =>
        other is not null && Service == other.Service && Action == other.Action && Arguments.SequenceEqual(other.Arguments);

    public override int GetHashCode() => HashCode.Combine(Service, Action, Arguments.Count);
}

/// Where playback is on the TV, in milliseconds. A duration of 0 means the TV doesn't know it, as for photos.
public sealed record CastPosition(long Position, long Duration);

public enum CastState
{
    Playing,
    Paused,
    Stopped,
    Loading,
}

public static class CastStates
{
    public static CastState? FromWire(string? state) => state?.Trim().ToUpperInvariant() switch
    {
        "PLAYING" => CastState.Playing,
        "PAUSED_PLAYBACK" or "PAUSED_RECORDING" => CastState.Paused,
        "STOPPED" or "NO_MEDIA_PRESENT" => CastState.Stopped,
        "TRANSITIONING" => CastState.Loading,
        _ => null,
    };
}

/// The AVTransport service: what to play, and play, pause, stop and seek.
public static class AvTransport
{
    public const string Service = "urn:schemas-upnp-org:service:AVTransport:1";
    public const string ServicePrefix = "urn:schemas-upnp-org:service:AVTransport:";

    public static SoapCall SetUri(string url, string title, string mime, long? size = null) =>
        Call("SetAVTransportURI", ("CurrentURI", url), ("CurrentURIMetaData", Metadata(url, title, mime, size)));

    public static SoapCall Play() => Call("Play", ("Speed", "1"));

    public static SoapCall Pause() => Call("Pause");

    public static SoapCall Stop() => Call("Stop");

    public static SoapCall Seek(long positionMs) => Call("Seek", ("Unit", "REL_TIME"), ("Target", Time(positionMs)));

    public static SoapCall PositionInfo() => Call("GetPositionInfo");

    public static SoapCall TransportInfo() => Call("GetTransportInfo");

    public static CastPosition? Position(string response)
    {
        if (Xml.Parse(response) is not XElement root) return null;
        if (Xml.DescendantText(root, "RelTime") is not string relTime || ParseTime(relTime) is not long position) return null;

        var duration = Xml.DescendantText(root, "TrackDuration") is string text ? ParseTime(text) ?? 0 : 0;

        return new CastPosition(position, duration);
    }

    public static CastState? State(string response) =>
        Xml.Parse(response) is XElement root ? CastStates.FromWire(Xml.DescendantText(root, "CurrentTransportState")) : null;

    /// The DIDL-Lite description TVs show as the title, and use to pick a player.
    public static string Metadata(string url, string title, string mime, long? size = null)
    {
        var kind = CastKinds.Of(mime) ?? CastKind.Video;
        var sizeAttribute = size is >= 0 ? $" size=\"{size}\"" : "";

        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" " +
            "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">" +
            "<item id=\"0\" parentID=\"-1\" restricted=\"1\">" +
            $"<dc:title>{Xml.Escape(title)}</dc:title>" +
            $"<upnp:class>{kind.UpnpClass()}</upnp:class>" +
            $"<res protocolInfo=\"http-get:*:{Xml.Escape(mime)}:*\"{sizeAttribute}>{Xml.Escape(url)}</res>" +
            "</item></DIDL-Lite>";
    }

    /// "1:02:03" for 3,723,000 ms.
    public static string Time(long ms)
    {
        var seconds = Math.Max(ms / 1000, 0);

        return string.Create(CultureInfo.InvariantCulture, $"{seconds / 3600}:{seconds / 60 % 60:00}:{seconds % 60:00}");
    }

    /// Milliseconds in "H:MM:SS" or "H:MM:SS.fff", or null for "NOT_IMPLEMENTED" and other text.
    public static long? ParseTime(string text)
    {
        var parts = text.Trim().Split(':');
        if (parts.Length != 3) return null;

        if (!long.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out var hours)) return null;
        if (!long.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var minutes)) return null;
        if (!double.TryParse(parts[2], NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var seconds)) return null;

        return (hours * 3600 + minutes * 60) * 1000 + (long)(seconds * 1000);
    }

    private static SoapCall Call(string action, params (string Name, string Value)[] arguments) =>
        new(Service, action, [new("InstanceID", "0"), .. arguments.Select(a => new KeyValuePair<string, string>(a.Name, a.Value))]);
}

/// The RenderingControl service: the TV's volume, from 0 to 100.
public static class RenderingControl
{
    public const string Service = "urn:schemas-upnp-org:service:RenderingControl:1";
    public const string ServicePrefix = "urn:schemas-upnp-org:service:RenderingControl:";

    public static SoapCall SetVolume(int volume) =>
        Call("SetVolume", ("DesiredVolume", Math.Clamp(volume, 0, 100).ToString(CultureInfo.InvariantCulture)));

    public static SoapCall GetVolume() => Call("GetVolume");

    public static int? Volume(string response) =>
        Xml.Parse(response) is XElement root && int.TryParse(Xml.DescendantText(root, "CurrentVolume")?.Trim(), out var volume) ? volume : null;

    private static SoapCall Call(string action, params (string Name, string Value)[] arguments) =>
        new(Service, action, [new("InstanceID", "0"), new("Channel", "Master"), .. arguments.Select(a => new KeyValuePair<string, string>(a.Name, a.Value))]);
}

/// The part of a file asked for by an HTTP Range header. End is inclusive.
public sealed record ByteRange(long Start, long End)
{
    public long Length => End - Start + 1;

    /// False when the range starts past the end of the file.
    public bool IsSatisfiable => Start <= End;

    /// Null when there is no single byte range to honour, so the whole file is sent.
    public static ByteRange? Parse(string? header, long size)
    {
        var trimmed = header?.Trim();
        if (trimmed is null || !trimmed.StartsWith("bytes=", StringComparison.OrdinalIgnoreCase)) return null;

        var spec = trimmed[6..].Trim();
        if (spec.Contains(',')) return null;

        var dash = spec.IndexOf('-');
        if (dash < 0) return null;

        var first = spec[..dash].Trim();
        var last = spec[(dash + 1)..].Trim();

        if (first.Length == 0)
        {
            if (!long.TryParse(last, out var suffix) || suffix <= 0) return null;
            return new ByteRange(Math.Max(size - suffix, 0), size - 1);
        }

        if (!long.TryParse(first, out var start)) return null;

        long asked;
        if (last.Length == 0) asked = size - 1;
        else if (!long.TryParse(last, out asked)) return null;

        if (start >= size) return new ByteRange(start, start - 1);
        if (asked < start) return null;

        return new ByteRange(start, Math.Min(asked, size - 1));
    }
}

/// The request line and headers of an HTTP request, with header names in lower case.
public sealed record HttpRequestHead(string Method, string Path, IReadOnlyDictionary<string, string> Headers)
{
    public static HttpRequestHead? Parse(string head)
    {
        var lines = head.Replace("\r\n", "\n").Split('\n');
        var parts = lines[0].Split(' ');
        if (parts.Length < 2) return null;

        return new HttpRequestHead(parts[0].ToUpperInvariant(), parts[1], HttpHeaders.Parse(lines.Skip(1), upper: false));
    }

    public bool Equals(HttpRequestHead? other) =>
        other is not null && Method == other.Method && Path == other.Path &&
        Headers.Count == other.Headers.Count && Headers.All(h => other.Headers.TryGetValue(h.Key, out var value) && value == h.Value);

    public override int GetHashCode() => HashCode.Combine(Method, Path);
}

internal static class HttpHeaders
{
    public static Dictionary<string, string> Parse(IEnumerable<string> lines, bool upper)
    {
        var headers = new Dictionary<string, string>();

        foreach (var line in lines)
        {
            var colon = line.IndexOf(':');
            if (colon <= 0) continue;

            var name = line[..colon].Trim();
            headers[upper ? name.ToUpperInvariant() : name.ToLowerInvariant()] = line[(colon + 1)..].Trim();
        }

        return headers;
    }
}

/// Namespace-blind lookups over a parsed XML document.
internal static class Xml
{
    public static XElement? Parse(string text)
    {
        try
        {
            var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null };
            using var reader = XmlReader.Create(new StringReader(text.Trim()), settings);

            return XDocument.Load(reader).Root;
        }
        catch (XmlException)
        {
            return null;
        }
    }

    public static IEnumerable<XElement> Children(XElement element, string name) => element.Elements().Where(e => e.Name.LocalName == name);

    public static XElement? Child(XElement element, string name) => Children(element, name).FirstOrDefault();

    public static string? Text(XElement element, string name) => Child(element, name)?.Value.Trim() is { Length: > 0 } text ? text : null;

    public static IEnumerable<XElement> Descendants(XElement element, string name) => element.Descendants().Where(e => e.Name.LocalName == name);

    public static string? DescendantText(XElement element, string name) => Descendants(element, name).FirstOrDefault()?.Value;

    public static string Escape(string text)
    {
        var escaped = new StringBuilder(text.Length);

        foreach (var c in text)
        {
            escaped.Append(c switch
            {
                '&' => "&amp;",
                '<' => "&lt;",
                '>' => "&gt;",
                '"' => "&quot;",
                '\'' => "&apos;",
                _ => c.ToString(),
            });
        }

        return escaped.ToString();
    }
}
