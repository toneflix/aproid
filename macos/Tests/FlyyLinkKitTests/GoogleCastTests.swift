import XCTest
@testable import FlyyLinkKit

final class GoogleCastTests: XCTestCase {
    private let pingHex =
        "0800120873656e6465722d301a0a72656365697665722d30222775726e3a782d636173743a636f6d2e676f6f676c652e636173742e74702e6865617274626561742800320f7b2274797065223a2250494e47227d"

    // One answer from a Cast TV: a PTR to its instance, then TXT, SRV and A records, with compressed names.
    private let answerHex =
        "0000840000000001000000030b5f676f6f676c6563617374045f746370056c6f63616c00000c000100000078001e1b416e64726f69642d54562d31613262336334643565366637613862c00cc02e0010800100001194003e1369643d316132623363346435653666376138620f6d643d4869536d617274545620413411666e3d4c6976696e6720526f6f6d2054560763613d32303533c02e00218001000000780016000000001f49083161326233633464056c6f63616c00c0a800018001000000780004c0a8011e"

    func testEncodesCastMessages() {
        let message = CastMessage(source: GoogleCast.sender, destination: GoogleCast.receiver, namespace: GoogleCast.heartbeat, payload: #"{"type":"PING"}"#)

        XCTAssertEqual(hex(message.encode()), pingHex)
        XCTAssertEqual(CastMessage.decode(unhex(pingHex)), message)
    }

    func testIgnoresBrokenCastMessages() {
        XCTAssertNil(CastMessage.decode(Array(unhex(pingHex).prefix(20))))
        XCTAssertNil(CastMessage.decode([0x08, 0x00]))
    }

    func testMdnsQueryAsksForCastTvs() {
        XCTAssertEqual(hex(Mdns.query()), "0000000000010000000000000b5f676f6f676c6563617374045f746370056c6f63616c00000c8001")
    }

    func testReadsCastTvsFromMdnsAnswers() {
        let tvs = Mdns.castTvs(Mdns.parse(unhex(answerHex)), sender: "192.168.1.99")

        XCTAssertEqual(tvs, [TvRenderer(id: "cast:1a2b3c4d5e6f7a8b", name: "Living Room TV", cast: CastEndpoint(host: "192.168.1.30", port: 8009))])
        XCTAssertEqual(tvs.first?.host, "192.168.1.30")
    }

    func testIgnoresMdnsQuestions() {
        XCTAssertTrue(Mdns.parse(Mdns.query()).isEmpty)
        XCTAssertTrue(Mdns.parse([1, 2, 3]).isEmpty)
    }

    func testLoadsMediaOnTheDefaultReceiver() throws {
        let load = try XCTUnwrap(GoogleCast.parse(GoogleCast.encode(GoogleCast.load(7, url: "http://192.168.1.5:4000/t/song.mp3", title: "Song", mime: "audio/mpeg"))))
        let media = try XCTUnwrap(load["media"] as? CastJson)
        let metadata = try XCTUnwrap(media["metadata"] as? CastJson)

        XCTAssertEqual(GoogleCast.type(load), "LOAD")
        XCTAssertEqual(GoogleCast.requestId(load), 7)
        XCTAssertEqual(load["autoplay"] as? Bool, true)
        XCTAssertEqual(media["contentId"] as? String, "http://192.168.1.5:4000/t/song.mp3")
        XCTAssertEqual(media["contentType"] as? String, "audio/mpeg")
        XCTAssertEqual(metadata["metadataType"] as? Int, 3)
        XCTAssertEqual(metadata["title"] as? String, "Song")
        XCTAssertEqual(GoogleCast.launch(1)["appId"] as? String, "CC1AD845")
        XCTAssertEqual(GoogleCast.seek(2, mediaSessionId: 3, positionMs: 12_500)["currentTime"] as? Double, 12.5)
    }

    func testReadsMediaStatus() throws {
        let status = try XCTUnwrap(GoogleCast.parse(
            #"{"type":"MEDIA_STATUS","requestId":4,"status":[{"mediaSessionId":3,"playerState":"PAUSED","currentTime":12.5,"media":{"duration":60}}]}"#
        ))

        XCTAssertEqual(GoogleCast.media(status), CastMedia(mediaSessionId: 3, state: .paused, position: CastPosition(position: 12_500, duration: 60_000)))
        XCTAssertEqual(GoogleCast.media(try XCTUnwrap(GoogleCast.parse(#"{"type":"MEDIA_STATUS","status":[]}"#))), CastMedia(mediaSessionId: nil, state: .stopped, position: nil))
        XCTAssertEqual(GoogleCast.state("BUFFERING"), .loading)
        XCTAssertNil(GoogleCast.media(try XCTUnwrap(GoogleCast.parse(#"{"type":"RECEIVER_STATUS"}"#))))
    }

    func testReadsTheRunningMediaReceiver() throws {
        let status = try XCTUnwrap(GoogleCast.parse(
            #"{"type":"RECEIVER_STATUS","requestId":1,"status":{"volume":{"level":0.35},"applications":["#
                + #"{"appId":"E8C28D3C","sessionId":"other","transportId":"other-1"},"#
                + #"{"appId":"CC1AD845","sessionId":"abc","transportId":"web-5"}]}}"#
        ))

        XCTAssertEqual(GoogleCast.mediaApp(status), CastApp(sessionId: "abc", transportId: "web-5"))
        XCTAssertEqual(GoogleCast.volume(status), 35)
        XCTAssertNil(GoogleCast.mediaApp(try XCTUnwrap(GoogleCast.parse(#"{"type":"RECEIVER_STATUS","status":{"applications":[]}}"#))))
    }

    func testPrefersCastWhenATvAnswersBothWays() {
        let castTv = TvRenderer(id: "cast:1", name: "Living Room TV", cast: CastEndpoint(host: "192.168.1.30"))
        let sameTv = TvRenderer(id: "uuid:a", name: "Hisense DMR", avTransportUrl: "http://192.168.1.30:9197/av")
        let other = TvRenderer(id: "uuid:b", name: "bedroom", avTransportUrl: "http://192.168.1.31/av")

        XCTAssertEqual(TvFinder.merge(dlna: [sameTv, other], cast: [castTv]), [other, castTv])
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func unhex(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            bytes.append(UInt8(text[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }
}
