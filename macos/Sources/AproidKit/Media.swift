import Foundation

/// One media player on the phone, as "kdeconnect.mpris" describes it. Times are in milliseconds. Mirrors Media.kt.
public struct MediaPlayer: Equatable, Sendable {
    public var name: String
    public var title = ""
    public var artist = ""
    public var album = ""
    public var isPlaying = false
    public var position: Int64 = 0
    public var length: Int64 = 0
    public var volume: Int?
    public var canPlay = true
    public var canPause = true
    public var canGoNext = false
    public var canGoPrevious = false
    public var canSeek = false
    public var albumArtUrl: String?

    public init(name: String) {
        self.name = name
    }

    /// Nil unless the packet describes a player.
    public init?(packet: NetworkPacket) {
        guard packet.type == PacketType.mpris, packet.bool("transferringAlbumArt") != true,
              let name = packet.string("player")
        else { return nil }

        self.init(name: name)
        title = packet.string("title") ?? ""
        artist = packet.string("artist") ?? ""
        album = packet.string("album") ?? ""
        isPlaying = packet.bool("isPlaying") ?? false
        position = packet.int("pos") ?? 0
        length = packet.int("length") ?? 0
        volume = packet.int("volume").map { Int($0) }
        canPlay = packet.bool("canPlay") ?? true
        canPause = packet.bool("canPause") ?? true
        canGoNext = packet.bool("canGoNext") ?? false
        canGoPrevious = packet.bool("canGoPrevious") ?? false
        canSeek = packet.bool("canSeek") ?? false
        albumArtUrl = packet.string("albumArtUrl").flatMap { $0.isEmpty ? nil : $0 }
    }

    public func toPacket() -> NetworkPacket {
        var body: [String: JSONValue] = [
            "player": .string(name),
            "title": .string(title),
            "artist": .string(artist),
            "album": .string(album),
            "isPlaying": .bool(isPlaying),
            "pos": .int(position),
            "length": .int(length),
            "canPlay": .bool(canPlay),
            "canPause": .bool(canPause),
            "canGoNext": .bool(canGoNext),
            "canGoPrevious": .bool(canGoPrevious),
            "canSeek": .bool(canSeek),
        ]
        if let volume { body["volume"] = .int(Int64(volume)) }
        if let albumArtUrl { body["albumArtUrl"] = .string(albumArtUrl) }

        return NetworkPacket(type: PacketType.mpris, body: body)
    }
}

public enum MediaAction: String, Sendable {
    case playPause = "PlayPause"
    case play = "Play"
    case pause = "Pause"
    case next = "Next"
    case previous = "Previous"
    case stop = "Stop"
}

/// What the Mac asks of the phone's players ("kdeconnect.mpris.request").
public struct MediaRequest: Equatable, Sendable {
    public var player: String?
    public var wantsPlayerList = false
    public var wantsNowPlaying = false
    public var action: MediaAction?
    public var seekTo: Int64?
    public var volume: Int?
    public var albumArtUrl: String?

    public init(player: String? = nil) {
        self.player = player
    }

    public static func playerList() -> MediaRequest {
        var request = MediaRequest()
        request.wantsPlayerList = true
        return request
    }

    public static func nowPlaying(_ player: String) -> MediaRequest {
        var request = MediaRequest(player: player)
        request.wantsNowPlaying = true
        return request
    }

    public static func action(_ player: String, _ action: MediaAction) -> MediaRequest {
        var request = MediaRequest(player: player)
        request.action = action
        return request
    }

    public static func seek(_ player: String, to position: Int64) -> MediaRequest {
        var request = MediaRequest(player: player)
        request.seekTo = position
        return request
    }

    public static func volume(_ player: String, _ volume: Int) -> MediaRequest {
        var request = MediaRequest(player: player)
        request.volume = min(max(volume, 0), 100)
        return request
    }

    public static func albumArt(_ player: String, url: String) -> MediaRequest {
        var request = MediaRequest(player: player)
        request.albumArtUrl = url
        return request
    }

    public init?(packet: NetworkPacket) {
        guard packet.type == PacketType.mprisRequest else { return nil }

        self.init(player: packet.string("player"))
        wantsPlayerList = packet.bool("requestPlayerList") ?? false
        wantsNowPlaying = packet.bool("requestNowPlaying") ?? false
        action = packet.string("action").flatMap(MediaAction.init(rawValue:))
        seekTo = packet.int("SetPosition")
        volume = packet.int("setVolume").map { Int($0) }
        albumArtUrl = packet.string("albumArtUrl")
    }

    public func toPacket() -> NetworkPacket {
        var body: [String: JSONValue] = [:]
        if let player { body["player"] = .string(player) }
        if wantsPlayerList { body["requestPlayerList"] = true }
        if wantsNowPlaying {
            body["requestNowPlaying"] = true
            body["requestVolume"] = true
        }
        if let action { body["action"] = .string(action.rawValue) }
        if let seekTo { body["SetPosition"] = .int(seekTo) }
        if let volume { body["setVolume"] = .int(Int64(volume)) }
        if let albumArtUrl { body["albumArtUrl"] = .string(albumArtUrl) }

        return NetworkPacket(type: PacketType.mprisRequest, body: body)
    }
}

/// The other "kdeconnect.mpris" packets: the list of players, and album art sent as a payload.
public enum Media {
    public static func playerListPacket(_ names: [String]) -> NetworkPacket {
        NetworkPacket(
            type: PacketType.mpris,
            body: ["playerList": .array(names.map { .string($0) }), "supportAlbumArtPayload": true]
        )
    }

    /// The player names, or nil if the packet has no list.
    public static func playerList(_ packet: NetworkPacket) -> [String]? {
        guard packet.type == PacketType.mpris, packet.body["playerList"] != nil else { return nil }

        return packet.stringList("playerList")
    }

    /// Announces album art for `url`. Send it with `Device.sendWithPayload`.
    public static func albumArtPacket(player: String, url: String) -> NetworkPacket {
        NetworkPacket(
            type: PacketType.mpris,
            body: ["player": .string(player), "albumArtUrl": .string(url), "transferringAlbumArt": true]
        )
    }

    /// The art's url when the packet carries album art.
    public static func albumArtUrl(_ packet: NetworkPacket) -> String? {
        guard packet.type == PacketType.mpris, packet.bool("transferringAlbumArt") == true else { return nil }

        return packet.string("albumArtUrl")
    }
}
