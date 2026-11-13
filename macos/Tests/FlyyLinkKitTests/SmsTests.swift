import XCTest
@testable import FlyyLinkKit

final class SmsTests: XCTestCase {
    private let message = SmsMessage(
        id: 41,
        threadId: 7,
        body: "Running late, 10 min",
        addresses: [SmsAddress("+2348012345678", name: "Ada")],
        date: 1_700_000_000_000,
        isIncoming: true,
        isRead: false,
        subscriptionId: 1,
        attachments: [SmsAttachment(partId: 3, mimeType: "image/jpeg", uniqueId: "part-3", thumbnail: "aGVsbG8=")]
    )

    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    func testMessagesRoundTrip() throws {
        var sent = message
        sent.id = 42
        sent.body = "No worries"
        sent.isIncoming = false
        sent.isRead = true
        sent.attachments = []

        XCTAssertEqual(Sms.messages(try wire(Sms.messagesPacket([message, sent]))), [message, sent])
    }

    /// The same packet the Kotlin test reads.
    func testReadsKdeConnectMessage() throws {
        let packet = try NetworkPacket.parse(
            #"{"id":1,"type":"kdeconnect.sms.messages","body":{"version":2,"messages":[{"_id":"5","thread_id":2,"body":"hi","date":1700000000000,"type":2,"read":1,"event":1,"addresses":[{"address":"555"}]}]}}"#
        )

        let read = try XCTUnwrap(Sms.messages(packet)?.first)

        XCTAssertEqual(read.id, 5)
        XCTAssertFalse(read.isIncoming)
        XCTAssertEqual(read.addresses, [SmsAddress("555")])
    }

    func testRequestsRoundTrip() throws {
        XCTAssertEqual(
            Sms.conversationRequest(try wire(Sms.requestConversation(7, before: 1_700_000_000_000, count: 30))),
            Sms.ConversationRequest(threadId: 7, before: 1_700_000_000_000, count: 30)
        )
        XCTAssertEqual(
            Sms.conversationRequest(try wire(Sms.requestConversation(7))),
            Sms.ConversationRequest(threadId: 7, before: nil, count: 50)
        )
        XCTAssertEqual(
            Sms.sendRequest(try wire(Sms.send(to: ["+234801", "+234802"], body: "On my way", subscriptionId: 2))),
            Sms.SendRequest(addresses: ["+234801", "+234802"], body: "On my way", subscriptionId: 2)
        )
        XCTAssertEqual(Sms.requestConversations().type, PacketType.smsRequestConversations)
    }

    func testReadsVersionOneSendRequest() throws {
        let packet = try NetworkPacket.parse(#"{"id":1,"type":"kdeconnect.sms.request","body":{"phoneNumber":"555","messageBody":"yo"}}"#)

        XCTAssertEqual(Sms.sendRequest(packet), Sms.SendRequest(addresses: ["555"], body: "yo", subscriptionId: nil))
        XCTAssertNil(Sms.messages(packet))
    }
}
