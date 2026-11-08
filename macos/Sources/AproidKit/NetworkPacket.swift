import Foundation

public struct ProtocolError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// One KDE Connect packet. On the wire it is a single line of JSON ending in "\n".
public struct NetworkPacket: Equatable, Sendable {
    public var id: Int64
    public var type: String
    public var body: [String: JSONValue]
    public var payloadSize: Int64?
    public var payloadTransferInfo: [String: JSONValue]?

    public init(
        type: String,
        body: [String: JSONValue] = [:],
        id: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        payloadSize: Int64? = nil,
        payloadTransferInfo: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.type = type
        self.body = body
        self.payloadSize = payloadSize
        self.payloadTransferInfo = payloadTransferInfo
    }

    public func string(_ key: String) -> String? { body[key]?.stringValue }
    public func int(_ key: String) -> Int64? { body[key]?.intValue }
    public func bool(_ key: String) -> Bool? { body[key]?.boolValue }
    public func stringList(_ key: String) -> [String] {
        body[key]?.arrayValue?.compactMap { $0.stringValue } ?? []
    }

    public func serialize() throws -> Data {
        var root: [String: JSONValue] = [
            "id": .int(id),
            "type": .string(type),
            "body": .object(body),
        ]
        if let payloadSize { root["payloadSize"] = .int(payloadSize) }
        if let payloadTransferInfo { root["payloadTransferInfo"] = .object(payloadTransferInfo) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(root)
        data.append(0x0A)
        return data
    }

    public static func parse(_ data: Data) throws -> NetworkPacket {
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ProtocolError("invalid JSON")
        }
        guard case .object(let obj) = root else { throw ProtocolError("packet is not an object") }
        guard let type = obj["type"]?.stringValue else { throw ProtocolError("missing type") }
        // Some older clients send the id as a string.
        let id = obj["id"]?.intValue ?? obj["id"]?.stringValue.flatMap { Int64($0) } ?? 0
        var body: [String: JSONValue] = [:]
        if case .object(let b)? = obj["body"] { body = b }
        var info: [String: JSONValue]?
        if case .object(let i)? = obj["payloadTransferInfo"] { info = i }
        return NetworkPacket(type: type, body: body, id: id, payloadSize: obj["payloadSize"]?.intValue, payloadTransferInfo: info)
    }

    public static func parse(_ line: String) throws -> NetworkPacket {
        try parse(Data(line.utf8))
    }
}
