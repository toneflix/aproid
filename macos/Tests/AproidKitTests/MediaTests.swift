import XCTest
@testable import AproidKit

final class MediaTests: XCTestCase {
    private var player: MediaPlayer {
        var player = MediaPlayer(name: "Spotify")
        player.title = "Midnight City"
        player.artist = "M83"
        player.album = "Hurry Up, We're Dreaming"
        player.isPlaying = true
        player.position = 61_000
        player.length = 243_000
        player.volume = 70
        player.canGoNext = true
        player.canGoPrevious = true
        player.canSeek = true
        player.albumArtUrl = "flyylink://art/1f2e"
        return player
    }

    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    func testPlayerRoundTrips() throws {
        XCTAssertEqual(MediaPlayer(packet: try wire(player.toPacket())), player)
    }

    func testRequestsRoundTrip() throws {
        let requests: [MediaRequest] = [
            .playerList(),
            .nowPlaying("Spotify"),
            .action("Spotify", .next),
            .seek("Spotify", to: 90_000),
            .volume("Spotify", 140),
            .albumArt("Spotify", url: "flyylink://art/1f2e"),
        ]

        for request in requests {
            XCTAssertEqual(MediaRequest(packet: try wire(request.toPacket())), request)
        }
        XCTAssertEqual(MediaRequest.volume("Spotify", 140).volume, 100)
    }

    /// The same packet the Kotlin test reads.
    func testReadsKdeConnectRequest() throws {
        let packet = try NetworkPacket.parse(#"{"id":1,"type":"kdeconnect.mpris.request","body":{"player":"VLC","action":"PlayPause"}}"#)

        let request = MediaRequest(packet: packet)

        XCTAssertEqual(request?.player, "VLC")
        XCTAssertEqual(request?.action, .playPause)
    }

    func testPlayerListAndAlbumArtAreNotPlayers() throws {
        let list = try wire(Media.playerListPacket(["Spotify", "YouTube Music"]))
        let art = try wire(Media.albumArtPacket(player: "Spotify", url: "flyylink://art/1f2e"))

        XCTAssertEqual(Media.playerList(list), ["Spotify", "YouTube Music"])
        XCTAssertNil(MediaPlayer(packet: list))
        XCTAssertNil(MediaPlayer(packet: art))
        XCTAssertNil(Media.playerList(player.toPacket()))
        XCTAssertEqual(Media.albumArtUrl(art), "flyylink://art/1f2e")
    }
}
