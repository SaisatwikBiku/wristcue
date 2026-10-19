import XCTest
@testable import WristCueKit

/// Collects callback values. A main-actor class instead of a captured local `var`:
/// Swift 6 treats `@MainActor` closures as Sendable, and a Sendable closure may not
/// mutate a captured local variable.
@MainActor
private final class Recorder<Value: Sendable> {
    var values: [Value] = []
}

/// These tests pin down the delivery rules the apps rely on. Each test method is
/// `@MainActor` because the transport is main-actor isolated. Values are copied into
/// locals before XCTAssert, because XCTest's autoclosures are not main-actor isolated.
final class InMemoryTransportTests: XCTestCase {
    private func stateMessage(position: TimeInterval) -> WireMessage {
        WireMessage(payload: .state(Fixture.state(position: position)), sentAt: Fixture.t0)
    }

    private func commandMessage(id: Int) -> WireMessage {
        WireMessage(payload: .command(Fixture.command(.skip(seconds: 30), id: id)), sentAt: Fixture.t0)
    }

    @MainActor
    func testInteractiveMessageArrivesWhenReachable() async throws {
        let (phone, watch) = InMemoryTransport.makePair()
        let received = Recorder<WireMessage>()
        phone.onReceive = { received.values.append($0) }

        try await watch.sendInteractive(commandMessage(id: 1))

        let messages = received.values
        let channels = watch.sent.map(\.channel)
        XCTAssertEqual(messages, [commandMessage(id: 1)])
        XCTAssertEqual(channels, [.interactive])
    }

    @MainActor
    func testInteractiveMessageFailsWhenUnreachable() async {
        let (_, watch) = InMemoryTransport.makePair(reachable: false)
        var thrown: (any Error)?
        do {
            try await watch.sendInteractive(commandMessage(id: 1))
        } catch {
            thrown = error
        }
        let sentCount = watch.sent.count
        XCTAssertEqual(thrown as? TransportError, .notReachable)
        XCTAssertEqual(sentCount, 0)
    }

    @MainActor
    func testLatestValueKeepsOnlyNewestWhileUnreachable() throws {
        let (phone, watch) = InMemoryTransport.makePair(reachable: false)
        let received = Recorder<WireMessage>()
        watch.onReceive = { received.values.append($0) }

        for position in [1.0, 2.0, 3.0] {
            try phone.publishLatest(stateMessage(position: position))
        }
        let beforeReconnect = received.values.count
        phone.setReachable(true)

        let messages = received.values
        let handedOver = phone.sent.count
        XCTAssertEqual(beforeReconnect, 0)
        XCTAssertEqual(messages, [stateMessage(position: 3)])
        XCTAssertEqual(handedOver, 3, "All three were handed over; only the newest was delivered")
    }

    @MainActor
    func testLatestValueSlotsAreIndependentPerKind() throws {
        let (phone, watch) = InMemoryTransport.makePair(reachable: false)
        let received = Recorder<WireMessage.Kind>()
        watch.onReceive = { received.values.append($0.kind) }

        try phone.publishLatest(stateMessage(position: 1))
        try phone.publishLatest(WireMessage(
            payload: .bookmarks(BookmarkList(episodeID: "glance", bookmarks: [])),
            sentAt: Fixture.t0
        ))
        phone.setReachable(true)

        let kinds = Set(received.values)
        XCTAssertEqual(kinds, [.state, .bookmarks])
    }

    @MainActor
    func testGuaranteedTransfersArriveInOrderAfterReconnect() throws {
        let (phone, watch) = InMemoryTransport.makePair(reachable: false)
        let received = Recorder<WireMessage>()
        phone.onReceive = { received.values.append($0) }

        for id in 1...3 {
            try watch.transferGuaranteed(commandMessage(id: id))
        }
        watch.setReachable(true)

        let messages = received.values
        XCTAssertEqual(messages, [1, 2, 3].map { commandMessage(id: $0) })
    }

    @MainActor
    func testGuaranteedTransferArrivesImmediatelyWhenReachable() throws {
        let (phone, watch) = InMemoryTransport.makePair()
        let received = Recorder<WireMessage>()
        phone.onReceive = { received.values.append($0) }

        try watch.transferGuaranteed(commandMessage(id: 1))

        let count = received.values.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testReachabilityChangeNotifiesBothEndsOncePerChange() {
        let (phone, watch) = InMemoryTransport.makePair(reachable: true)
        let phoneEvents = Recorder<Bool>()
        let watchEvents = Recorder<Bool>()
        phone.onReachabilityChange = { phoneEvents.values.append($0) }
        watch.onReachabilityChange = { watchEvents.values.append($0) }

        watch.setReachable(false)
        watch.setReachable(false)
        phone.setReachable(true)

        let phoneSeen = phoneEvents.values
        let watchSeen = watchEvents.values
        let bothReachable = phone.isReachable && watch.isReachable
        XCTAssertEqual(phoneSeen, [false, true])
        XCTAssertEqual(watchSeen, [false, true])
        XCTAssertTrue(bothReachable)
    }

    @MainActor
    func testRecordsEncodedSize() throws {
        let (phone, _) = InMemoryTransport.makePair()
        let message = stateMessage(position: 1)

        try phone.publishLatest(message)

        let recorded = phone.sent.first?.byteCount
        let expected = try MessageCodec().encode(message).count
        XCTAssertEqual(recorded, expected)
        XCTAssertGreaterThan(expected, 0)
    }
}
