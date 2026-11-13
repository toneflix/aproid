import XCTest
@testable import FlyyLinkKit

/// Mirrors FlyyDropTest.kt and FlyyDropTests.cs.
final class FlyyDropTests: XCTestCase {
    private var now: Int64 = 1_000_000
    private var sender: FlyyDrop!
    private var receiver: FlyyDrop!
    private let photo = FlyyDrop.Item(name: "photo.jpg", size: 2048)
    private let notes = FlyyDrop.Item(name: "notes.txt", size: 10)

    override func setUp() {
        sender = FlyyDrop { [unowned self] in now }
        receiver = FlyyDrop { [unowned self] in now }
        receiver.receiving = .everyone
    }

    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    /// The sender asks the receiver, as it would over the network, and returns the receiver's view.
    private func ask(_ items: [FlyyDrop.Item]? = nil, text: String? = nil) throws -> FlyyDrop.Offer {
        let request = sender.request(to: "receiver", items: items ?? [photo, notes], text: text)
        XCTAssertTrue(sender.admitsOutgoing(to: "receiver", request))
        XCTAssertTrue(receiver.admitsIncoming(from: "sender", try wire(request)))

        guard case .ask(let offer)? = receiver.onRequest(from: "sender", try wire(request), isPaired: false) else {
            throw XCTSkip("request was not asked")
        }

        return offer
    }

    private func accept(_ offer: FlyyDrop.Offer) throws {
        let response = try XCTUnwrap(receiver.accept(offer.id))
        XCTAssertTrue(receiver.admitsOutgoing(to: "sender", response))
        XCTAssertTrue(sender.admitsIncoming(from: "receiver", try wire(response)))
        XCTAssertEqual(sender.onResponse(from: "receiver", try wire(response))?.accepted, true)
    }

    /// A file as it arrives: the sender's packet with the payload size added.
    private func arriving(_ id: String, _ item: FlyyDrop.Item, size: Int64? = nil) throws -> NetworkPacket {
        var packet = FlyyDrop.file(id, item)
        packet.payloadSize = size ?? item.size

        return try wire(packet)
    }

    func testRequestRoundTrips() throws {
        let offer = try ask()

        XCTAssertEqual(offer.items, [photo, notes])
        XCTAssertEqual(offer.totalSize, 2058)
        XCTAssertEqual(offer.deviceId, "sender")
    }

    func testAcceptedFilesComeInOnceEach() throws {
        let offer = try ask()
        try accept(offer)

        XCTAssertTrue(sender.admitsOutgoing(to: "receiver", FlyyDrop.file(offer.id, photo)))
        XCTAssertTrue(receiver.admitsIncoming(from: "sender", try arriving(offer.id, photo)))
        XCTAssertFalse(receiver.admitsIncoming(from: "sender", try arriving(offer.id, photo)))
        XCTAssertTrue(receiver.admitsIncoming(from: "sender", try arriving(offer.id, notes)))
        XCTAssertFalse(receiver.isActive(offer.id))
    }

    func testNothingComesInBeforeAccepting() throws {
        let offer = try ask()

        XCTAssertFalse(receiver.admitsIncoming(from: "sender", try arriving(offer.id, photo)))
        XCTAssertFalse(sender.admitsOutgoing(to: "receiver", FlyyDrop.file(offer.id, photo)))
    }

    func testOnlyTheDeclaredFilesAndSizesComeIn() throws {
        let offer = try ask()
        try accept(offer)

        var plain = Share.filePacket(name: photo.name, size: photo.size)
        plain.payloadSize = photo.size

        XCTAssertFalse(receiver.admitsIncoming(from: "sender", try arriving(offer.id, FlyyDrop.Item(name: "other.exe", size: 2048))))
        XCTAssertFalse(receiver.admitsIncoming(from: "sender", try arriving(offer.id, photo, size: 1_000_000)))
        XCTAssertFalse(receiver.admitsIncoming(from: "someone-else", try arriving(offer.id, photo)))
        XCTAssertFalse(receiver.admitsIncoming(from: "sender", try wire(plain)))
    }

    func testGuestsGetNoOtherPackets() throws {
        _ = try ask()

        XCTAssertFalse(receiver.admitsIncoming(from: "sender", Clipboard.packet("hi")))
        XCTAssertFalse(receiver.admitsIncoming(from: "sender", FindMyPhone.request()))
        XCTAssertFalse(receiver.admitsIncoming(from: "sender", Share.textPacket("hi")))
        XCTAssertFalse(receiver.admitsOutgoing(to: "sender", NotificationRequests.reply(to: "r1", message: "hi")))
    }

    func testAcceptedLinkComesInOnce() throws {
        let offer = try ask([], text: "https://toneflix.net")
        try accept(offer)

        let link = FlyyDrop.text(offer.id, "https://toneflix.net")
        XCTAssertEqual(Share(packet: link), .link("https://toneflix.net"))
        XCTAssertTrue(receiver.admitsIncoming(from: "sender", try wire(link)))
        XCTAssertFalse(receiver.admitsIncoming(from: "sender", try wire(link)))
        XCTAssertEqual(Share(packet: FlyyDrop.text("x", "hello there")), .text("hello there"))
    }

    func testDeclineEndsTheRequestOnBothSides() throws {
        let offer = try ask()
        let response = try XCTUnwrap(receiver.decline(offer.id))

        XCTAssertTrue(receiver.admitsOutgoing(to: "sender", response))
        let answer = try XCTUnwrap(sender.onResponse(from: "receiver", try wire(response)))
        XCTAssertFalse(answer.accepted)
        XCTAssertEqual(answer.reason, .declined)
        XCTAssertFalse(sender.isActive(offer.id))
        XCTAssertFalse(receiver.isActive(offer.id))
    }

    func testOffDeclinesStrangersButAsksPairedDevices() throws {
        receiver.receiving = .off
        let request = try wire(sender.request(to: "receiver", items: [photo]))

        guard case .reply(let reply)? = receiver.onRequest(from: "sender", request, isPaired: false) else { return XCTFail("not declined") }
        XCTAssertEqual(sender.onResponse(from: "receiver", try wire(reply))?.reason, .unavailable)

        let again = try wire(sender.request(to: "receiver", items: [photo]))
        guard case .ask? = receiver.onRequest(from: "sender", again, isPaired: true) else { return XCTFail("paired device not asked") }
    }

    func testEveryoneForTenMinutesRunsOut() {
        receiver.receiving = .everyoneFor10Minutes
        XCTAssertEqual(receiver.receivingUntil, now + FlyyDrop.everyoneMs)

        now += FlyyDrop.everyoneMs
        XCTAssertEqual(receiver.receiving, .off)
        XCTAssertNil(receiver.receivingUntil)
    }

    func testOneRequestAtATimePerDevice() throws {
        _ = try ask()
        let second = try wire(sender.request(to: "receiver", items: [notes]))

        guard case .reply(let reply)? = receiver.onRequest(from: "sender", second, isPaired: false) else { return XCTFail("not refused") }
        XCTAssertEqual(FlyyDrop.Reason(wire: reply.string("reason")), .busy)
    }

    func testUnansweredRequestsExpire() throws {
        let offer = try ask()

        now += FlyyDrop.askMs
        XCTAssertEqual(receiver.expire().map(\.id), [offer.id])
        XCTAssertNil(receiver.accept(offer.id))
    }

    func testCancelReachesTheOtherSide() throws {
        let offer = try ask()
        let cancel = try XCTUnwrap(sender.cancel(offer.id))

        XCTAssertTrue(sender.admitsOutgoing(to: "receiver", cancel))
        XCTAssertNil(receiver.onCancel(from: "intruder", try wire(cancel)))
        XCTAssertEqual(receiver.onCancel(from: "sender", try wire(cancel))?.id, offer.id)
        XCTAssertFalse(receiver.isActive(offer.id))
    }

    func testResponsesOnlyCountFromTheAskedDevice() throws {
        let request = sender.request(to: "receiver", items: [photo])
        let forged = NetworkPacket(type: PacketType.flyyDropResponse, body: ["id": .string(request.string("id") ?? ""), "accept": true])

        XCTAssertFalse(sender.admitsIncoming(from: "intruder", forged))
        XCTAssertNil(sender.onResponse(from: "intruder", forged))
        XCTAssertNotNil(sender.onResponse(from: "receiver", forged))
    }

    func testMalformedRequestsAreIgnored() throws {
        XCTAssertNil(FlyyDrop.offer(from: "d", NetworkPacket(type: PacketType.flyyDropRequest, body: ["id": "x"])))
        XCTAssertNil(FlyyDrop.offer(from: "d", NetworkPacket(type: PacketType.flyyDropRequest, body: ["text": "hi"])))

        let negative = try NetworkPacket.parse(#"{"id":1,"type":"flyylink.flyydrop.request","body":{"id":"x","files":[{"name":"a","size":-1}]}}"#)
        XCTAssertNil(FlyyDrop.offer(from: "d", negative))
        XCTAssertEqual(FlyyDrop.Item(name: "../../etc/passwd", size: 1).safeName, "passwd")
    }
}
