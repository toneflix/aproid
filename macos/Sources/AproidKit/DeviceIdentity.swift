import Foundation

public enum DeviceType: String, Sendable {
    case desktop, laptop, phone, tablet, tv
}

public struct DeviceIdentity: Equatable, Sendable {
    public var deviceId: String
    public var deviceName: String
    public var deviceType: DeviceType
    public var protocolVersion: Int
    public var incomingCapabilities: Set<String>
    public var outgoingCapabilities: Set<String>
    public var tcpPort: UInt16?

    public init(
        deviceId: String,
        deviceName: String,
        deviceType: DeviceType,
        protocolVersion: Int = AproidKit.protocolVersion,
        incomingCapabilities: Set<String> = Capabilities.mvp,
        outgoingCapabilities: Set<String> = Capabilities.mvp,
        tcpPort: UInt16? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.protocolVersion = protocolVersion
        self.incomingCapabilities = incomingCapabilities
        self.outgoingCapabilities = outgoingCapabilities
        self.tcpPort = tcpPort
    }

    public static func newDeviceId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    public static func isValidDeviceId(_ id: String) -> Bool {
        (32...38).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// Protocol v8 names are 1 to 32 characters with no punctuation from a fixed list.
    public static func sanitizeName(_ name: String, fallback: String = "Mac") -> String {
        let forbidden = Set("\"',;:.!?()[]<>")
        let cleaned = String(name.filter { !forbidden.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        let short = String(cleaned.prefix(32))
        return short.isEmpty ? fallback : short
    }

    public func toPacket() -> NetworkPacket {
        var body: [String: JSONValue] = [
            "deviceId": .string(deviceId),
            "deviceName": .string(deviceName),
            "deviceType": .string(deviceType.rawValue),
            "protocolVersion": .int(Int64(protocolVersion)),
            "incomingCapabilities": .array(incomingCapabilities.sorted().map { .string($0) }),
            "outgoingCapabilities": .array(outgoingCapabilities.sorted().map { .string($0) }),
        ]
        if let tcpPort { body["tcpPort"] = .int(Int64(tcpPort)) }
        return NetworkPacket(type: PacketType.identity, body: body)
    }

    public init(packet: NetworkPacket) throws {
        guard packet.type == PacketType.identity else { throw ProtocolError("not an identity packet: \(packet.type)") }
        guard let id = packet.string("deviceId") else { throw ProtocolError("missing deviceId") }
        guard Self.isValidDeviceId(id) else { throw ProtocolError("invalid deviceId") }
        self.init(
            deviceId: id,
            deviceName: Self.sanitizeName(packet.string("deviceName") ?? "", fallback: "Device"),
            deviceType: DeviceType(rawValue: packet.string("deviceType") ?? "") ?? .desktop,
            protocolVersion: Int(packet.int("protocolVersion") ?? 0),
            incomingCapabilities: Set(packet.stringList("incomingCapabilities")),
            outgoingCapabilities: Set(packet.stringList("outgoingCapabilities")),
            tcpPort: packet.int("tcpPort").flatMap { UInt16(exactly: $0) }
        )
    }
}
