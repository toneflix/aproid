import Foundation

/// SSDP, the multicast search that finds TVs and speakers able to play media sent over DLNA. Mirrors Dlna.kt.
public enum Ssdp {
    public static let address = "239.255.255.250"
    public static let port: UInt16 = 1900
    public static let renderer = "urn:schemas-upnp-org:device:MediaRenderer:1"

    public static func searchMessage(target: String = renderer, waitSeconds: Int = 2) -> String {
        "M-SEARCH * HTTP/1.1\r\n"
            + "HOST: \(address):\(port)\r\n"
            + "MAN: \"ssdp:discover\"\r\n"
            + "MX: \(waitSeconds)\r\n"
            + "ST: \(target)\r\n"
            + "\r\n"
    }

    /// Nil unless `message` is a search answer or an alive notice with a description location.
    public static func parse(_ message: String) -> SsdpReply? {
        let lines = message.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.first?.uppercased(), start.hasPrefix("HTTP/1.1 200") || start.hasPrefix("NOTIFY") else { return nil }

        let headers = HttpHeaders.parse(lines.dropFirst(), uppercase: true)
        if headers["NTS"] == "ssdp:byebye" { return nil }

        guard let location = headers["LOCATION"], location.hasPrefix("http") else { return nil }

        return SsdpReply(location: location, usn: headers["USN"] ?? "", target: headers["ST"] ?? headers["NT"] ?? "")
    }
}

public struct SsdpReply: Equatable, Sendable {
    public var location: String
    public var usn: String
    public var target: String
}

/// A TV or speaker that plays media from a URL: a DLNA one as its UPnP device description lists it, or a Google Cast one.
public struct TvRenderer: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var avTransportUrl: String
    public var renderingControlUrl: String?
    public var cast: CastEndpoint?

    public init(id: String, name: String, avTransportUrl: String = "", renderingControlUrl: String? = nil, cast: CastEndpoint? = nil) {
        self.id = id
        self.name = name
        self.avTransportUrl = avTransportUrl
        self.renderingControlUrl = renderingControlUrl
        self.cast = cast
    }

    /// The address of the TV, used to pick the local address it can reach us on.
    public var host: String { cast?.host ?? URL(string: avTransportUrl)?.host ?? "" }

    /// Reads the first device in `xml` that has an AVTransport service, resolving its URLs against `location`.
    public static func parse(_ xml: String, location: String) -> TvRenderer? {
        guard let root = XmlElement.parse(xml) else { return nil }

        let base = root.child("URLBase")?.text.trimmed.nonEmpty ?? location

        for device in root.descendants("device") {
            let services = device.child("serviceList")?.children("service") ?? []
            guard let transport = controlUrl(services, AvTransport.servicePrefix) else { continue }

            return TvRenderer(
                id: device.childText("UDN") ?? location,
                name: device.childText("friendlyName") ?? URL(string: location)?.host ?? location,
                avTransportUrl: resolve(base, transport),
                renderingControlUrl: controlUrl(services, RenderingControl.servicePrefix).map { resolve(base, $0) }
            )
        }

        return nil
    }

    private static func controlUrl(_ services: [XmlElement], _ typePrefix: String) -> String? {
        services.first { $0.childText("serviceType")?.hasPrefix(typePrefix) == true }?.childText("controlURL")
    }

    private static func resolve(_ base: String, _ url: String) -> String {
        URL(string: url.trimmed, relativeTo: URL(string: base))?.absoluteString ?? url
    }
}

/// What kind of media a file is, which picks how a TV shows it.
public enum CastKind: String, Sendable {
    case photo = "object.item.imageItem.photo"
    case video = "object.item.videoItem"
    case music = "object.item.audioItem.musicTrack"

    public var upnpClass: String { rawValue }

    /// Nil for anything a TV can't play, such as a document.
    public static func of(_ mime: String?) -> CastKind? {
        switch mime?.split(separator: "/").first?.lowercased() {
        case "image"?: return .photo
        case "video"?: return .video
        case "audio"?: return .music
        default: return nil
        }
    }
}

/// One UPnP action, sent as a SOAP request to a service's control URL.
public struct SoapCall: Equatable, Sendable {
    public var service: String
    public var action: String
    public var arguments: [(String, String)]

    public var soapAction: String { "\"\(service)#\(action)\"" }

    public func argument(_ name: String) -> String? {
        arguments.first { $0.0 == name }?.1
    }

    public func envelope() -> String {
        let body = arguments.map { "<\($0.0)>\(XmlElement.escape($0.1))</\($0.0)>" }.joined()

        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
            + "<s:Body><u:\(action) xmlns:u=\"\(service)\">\(body)</u:\(action)></s:Body></s:Envelope>"
    }

    public static func == (lhs: SoapCall, rhs: SoapCall) -> Bool {
        lhs.service == rhs.service && lhs.action == rhs.action && lhs.arguments.map { [$0.0, $0.1] } == rhs.arguments.map { [$0.0, $0.1] }
    }
}

/// Where playback is on the TV, in milliseconds. A duration of 0 means the TV doesn't know it, as for photos.
public struct CastPosition: Equatable, Sendable {
    public var position: Int64
    public var duration: Int64

    public init(position: Int64, duration: Int64) {
        self.position = position
        self.duration = duration
    }
}

public enum CastState: Sendable {
    case playing
    case paused
    case stopped
    case loading

    public static func fromWire(_ state: String?) -> CastState? {
        switch state?.trimmed.uppercased() {
        case "PLAYING"?: return .playing
        case "PAUSED_PLAYBACK"?, "PAUSED_RECORDING"?: return .paused
        case "STOPPED"?, "NO_MEDIA_PRESENT"?: return .stopped
        case "TRANSITIONING"?: return .loading
        default: return nil
        }
    }
}

/// The AVTransport service: what to play, and play, pause, stop and seek.
public enum AvTransport {
    public static let service = "urn:schemas-upnp-org:service:AVTransport:1"
    public static let servicePrefix = "urn:schemas-upnp-org:service:AVTransport:"

    public static func setUri(_ url: String, title: String, mime: String, size: Int64? = nil) -> SoapCall {
        call("SetAVTransportURI", ("CurrentURI", url), ("CurrentURIMetaData", metadata(url, title: title, mime: mime, size: size)))
    }

    public static func play() -> SoapCall { call("Play", ("Speed", "1")) }

    public static func pause() -> SoapCall { call("Pause") }

    public static func stop() -> SoapCall { call("Stop") }

    public static func seek(_ positionMs: Int64) -> SoapCall { call("Seek", ("Unit", "REL_TIME"), ("Target", time(positionMs))) }

    public static func positionInfo() -> SoapCall { call("GetPositionInfo") }

    public static func transportInfo() -> SoapCall { call("GetTransportInfo") }

    public static func position(_ response: String) -> CastPosition? {
        guard let root = XmlElement.parse(response),
              let position = root.descendantText("RelTime").flatMap(parseTime)
        else { return nil }

        return CastPosition(position: position, duration: root.descendantText("TrackDuration").flatMap(parseTime) ?? 0)
    }

    public static func state(_ response: String) -> CastState? {
        XmlElement.parse(response).flatMap { CastState.fromWire($0.descendantText("CurrentTransportState")) }
    }

    /// The DIDL-Lite description TVs show as the title, and use to pick a player.
    public static func metadata(_ url: String, title: String, mime: String, size: Int64? = nil) -> String {
        let kind = CastKind.of(mime) ?? .video
        let sizeAttribute = size.flatMap { $0 >= 0 ? " size=\"\($0)\"" : nil } ?? ""

        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" "
            + "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">"
            + "<item id=\"0\" parentID=\"-1\" restricted=\"1\">"
            + "<dc:title>\(XmlElement.escape(title))</dc:title>"
            + "<upnp:class>\(kind.upnpClass)</upnp:class>"
            + "<res protocolInfo=\"http-get:*:\(XmlElement.escape(mime)):*\"\(sizeAttribute)>\(XmlElement.escape(url))</res>"
            + "</item></DIDL-Lite>"
    }

    /// "1:02:03" for 3,723,000 ms.
    public static func time(_ ms: Int64) -> String {
        let seconds = max(ms / 1000, 0)

        return String(format: "%lld:%02lld:%02lld", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    /// Milliseconds in "H:MM:SS" or "H:MM:SS.fff", or nil for "NOT_IMPLEMENTED" and other text.
    public static func parseTime(_ text: String) -> Int64? {
        let parts = text.trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let hours = Int64(parts[0]),
              let minutes = Int64(parts[1]),
              let seconds = Double(parts[2])
        else { return nil }

        return (hours * 3600 + minutes * 60) * 1000 + Int64(seconds * 1000)
    }

    private static func call(_ action: String, _ arguments: (String, String)...) -> SoapCall {
        SoapCall(service: service, action: action, arguments: [("InstanceID", "0")] + arguments)
    }
}

/// The RenderingControl service: the TV's volume, from 0 to 100.
public enum RenderingControl {
    public static let service = "urn:schemas-upnp-org:service:RenderingControl:1"
    public static let servicePrefix = "urn:schemas-upnp-org:service:RenderingControl:"

    public static func setVolume(_ volume: Int) -> SoapCall { call("SetVolume", ("DesiredVolume", String(min(max(volume, 0), 100)))) }

    public static func getVolume() -> SoapCall { call("GetVolume") }

    public static func volume(_ response: String) -> Int? {
        XmlElement.parse(response)?.descendantText("CurrentVolume").flatMap { Int($0.trimmed) }
    }

    private static func call(_ action: String, _ arguments: (String, String)...) -> SoapCall {
        SoapCall(service: service, action: action, arguments: [("InstanceID", "0"), ("Channel", "Master")] + arguments)
    }
}

/// The part of a file asked for by an HTTP Range header. `end` is inclusive.
public struct ByteRange: Equatable, Sendable {
    public var start: Int64
    public var end: Int64

    public init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }

    public var length: Int64 { end - start + 1 }

    /// False when the range starts past the end of the file.
    public var isSatisfiable: Bool { start <= end }

    /// Nil when there is no single byte range to honour, so the whole file is sent.
    public static func parse(_ header: String?, size: Int64) -> ByteRange? {
        guard let header = header?.trimmed, header.lowercased().hasPrefix("bytes=") else { return nil }

        let spec = header.dropFirst(6).trimmingCharacters(in: .whitespaces)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return nil }

        let first = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let last = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)

        if first.isEmpty {
            guard let suffix = Int64(last), suffix > 0 else { return nil }
            return ByteRange(start: max(size - suffix, 0), end: size - 1)
        }

        guard let start = Int64(first) else { return nil }
        guard let asked = last.isEmpty ? size - 1 : Int64(last) else { return nil }
        if start >= size { return ByteRange(start: start, end: start - 1) }
        if asked < start { return nil }

        return ByteRange(start: start, end: min(asked, size - 1))
    }
}

/// The request line and headers of an HTTP request, with header names in lower case.
public struct HttpRequestHead: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]

    public init(method: String, path: String, headers: [String: String]) {
        self.method = method
        self.path = path
        self.headers = headers
    }

    public static func parse(_ head: String) -> HttpRequestHead? {
        let lines = head.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        guard let parts = lines.first?.split(separator: " "), parts.count >= 2 else { return nil }

        return HttpRequestHead(method: parts[0].uppercased(), path: String(parts[1]), headers: HttpHeaders.parse(lines.dropFirst(), uppercase: false))
    }
}

enum HttpHeaders {
    static func parse<S: Sequence>(_ lines: S, uppercase: Bool) -> [String: String] where S.Element == Substring {
        var headers: [String: String] = [:]

        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { continue }

            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[uppercase ? name.uppercased() : name.lowercased()] = value
        }

        return headers
    }
}

/// A parsed XML element with namespace prefixes dropped, enough to read UPnP descriptions and replies.
final class XmlElement {
    let name: String
    var text = ""
    var elements: [XmlElement] = []

    init(name: String) {
        self.name = name
    }

    static func parse(_ xml: String) -> XmlElement? {
        guard let data = xml.trimmed.data(using: .utf8) else { return nil }

        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder

        return parser.parse() ? builder.root : nil
    }

    func children(_ name: String) -> [XmlElement] { elements.filter { $0.name == name } }

    func child(_ name: String) -> XmlElement? { elements.first { $0.name == name } }

    func childText(_ name: String) -> String? { child(name)?.text.trimmed.nonEmpty }

    func descendants(_ name: String) -> [XmlElement] {
        elements.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }

    func descendantText(_ name: String) -> String? { descendants(name).first?.text }

    static func escape(_ text: String) -> String {
        var escaped = ""

        for c in text {
            switch c {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default: escaped.append(c)
            }
        }

        return escaped
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XmlElement?
        private var stack: [XmlElement] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            let element = XmlElement(name: elementName.split(separator: ":").last.map(String.init) ?? elementName)
            stack.last?.elements.append(element)
            if root == nil { root = element }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
