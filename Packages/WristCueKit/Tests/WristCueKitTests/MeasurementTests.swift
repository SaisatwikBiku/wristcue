import XCTest
@testable import WristCueKit

final class LatencySummaryTests: XCTestCase {
    func testNoSamplesHasNoSummary() {
        XCTAssertNil(LatencySummary(samples: []))
        XCTAssertNil(LatencySummary(samples: [.nan, .infinity]))
    }

    func testOddCountMedianIsTheMiddleSample() throws {
        let summary = try XCTUnwrap(LatencySummary(samples: [0.3, 0.1, 0.2]))
        XCTAssertEqual(summary.median, 0.2)
        XCTAssertEqual(summary.min, 0.1)
        XCTAssertEqual(summary.max, 0.3)
        XCTAssertEqual(summary.count, 3)
    }

    func testEvenCountMedianAveragesTheMiddlePair() throws {
        let summary = try XCTUnwrap(LatencySummary(samples: [4, 1, 3, 2]))
        XCTAssertEqual(summary.median, 2.5)
    }

    func testP95IsNearestRank() throws {
        // 40 samples: rank ceil(0.95 * 40) = 38. 20 samples: rank 19.
        let forty = try XCTUnwrap(LatencySummary(samples: (1...40).map(Double.init).shuffled()))
        let twenty = try XCTUnwrap(LatencySummary(samples: (1...20).map(Double.init)))
        let one = try XCTUnwrap(LatencySummary(samples: [7]))
        XCTAssertEqual(forty.p95, 38)
        XCTAssertEqual(twenty.p95, 19)
        XCTAssertEqual(one.p95, 7)
    }

    func testNonFiniteSamplesAreIgnored() throws {
        let summary = try XCTUnwrap(LatencySummary(samples: [1, .nan, 3]))
        XCTAssertEqual(summary.count, 2)
    }
}

final class TrafficCounterTests: XCTestCase {
    func testTalliesPerChannelAndDirection() {
        var counter = TrafficCounter(startedAt: Fixture.t0)
        counter.record(.interactive, .sent, bytes: 100)
        counter.record(.interactive, .sent, bytes: 50)
        counter.record(.latest, .received, bytes: 300)

        XCTAssertEqual(counter.tally(.interactive, .sent), TrafficCounter.Tally(messages: 2, bytes: 150))
        XCTAssertEqual(counter.tally(.guaranteed, .sent), TrafficCounter.Tally())
        XCTAssertEqual(counter.total(.sent), TrafficCounter.Tally(messages: 2, bytes: 150))
        XCTAssertEqual(counter.total(.received), TrafficCounter.Tally(messages: 1, bytes: 300))
    }

    func testRatePerMinute() {
        let counter = TrafficCounter(startedAt: Fixture.t0)
        XCTAssertNil(counter.perMinute(10, now: Fixture.t0.addingTimeInterval(0.5)))
        XCTAssertEqual(counter.perMinute(10, now: Fixture.t0.addingTimeInterval(30)), 20)
    }

    func testResetClearsCountsAndRestartsTheClock() {
        var counter = TrafficCounter(startedAt: Fixture.t0)
        counter.record(.guaranteed, .sent, bytes: 10)
        let later = Fixture.t0.addingTimeInterval(100)

        counter.reset(at: later)

        XCTAssertEqual(counter.total(.sent), TrafficCounter.Tally())
        XCTAssertEqual(counter.startedAt, later)
    }
}

final class SyncModeTests: XCTestCase {
    func testModeComesFromLaunchArgumentsOrDefaultsToOptimized() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        XCTAssertEqual(SyncMode.fromDefaults(defaults), .optimized)
        defaults.set("naive", forKey: SyncMode.defaultsKey)
        XCTAssertEqual(SyncMode.fromDefaults(defaults), .naive)
        defaults.set("turbo", forKey: SyncMode.defaultsKey)
        XCTAssertEqual(SyncMode.fromDefaults(defaults), .optimized)
    }
}

/// Values are copied into locals before XCTAssert, whose autoclosures aren't
/// main-actor isolated.
final class MeasurementTests: XCTestCase {
    // MARK: Round trips

    @MainActor
    func testMeasuredSendReturnsTheRoundTrip() async {
        let world = World()
        world.phone.publish(world.app.state)

        let roundTrip = await world.watch.sendAndMeasure(.play)

        XCTAssertEqual(roundTrip, 0)
    }

    @MainActor
    func testMeasuredSendTimesOutWithoutAcknowledgement() async {
        let world = World()
        world.app.answers = false
        world.phone.publish(world.app.state)

        let roundTrip = await world.watch.sendAndMeasure(.play, timeout: .milliseconds(20))

        XCTAssertNil(roundTrip)
    }

    @MainActor
    func testRoundTripBenchmarkAlternatesVolume() async {
        let world = World()
        world.phone.publish(world.app.state)

        let results = await world.watch.measureRoundTrips(count: 4, gap: .zero)

        let measured = results.compactMap { $0 }.count
        let levels = world.app.executed.compactMap { command -> Double? in
            if case .setVolume(let level) = command.action { return level }
            return nil
        }
        XCTAssertEqual(measured, 4)
        XCTAssertEqual(levels.count, 4)
        XCTAssertEqual(levels[0], 0.45, accuracy: 0.0001)
        XCTAssertEqual(levels[1], 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testMeasuredRoundTripInNaiveMode() async {
        let world = World(mode: .naive)
        await world.phone.publish(world.app.state)?.value

        let roundTrip = await world.watch.sendAndMeasure(.play)

        XCTAssertEqual(roundTrip, 0)
    }

    // MARK: Naive mode

    @MainActor
    func testNaiveModeSendsEveryCrownTick() async {
        let world = World(mode: .naive)
        await world.phone.publish(world.app.state)?.value

        for level in [0.55, 0.6, 0.65] {
            await world.watch.setVolume(level)?.value
        }

        let executed = world.app.executed.count
        let interpolates = world.watch.interpolatesProgress
        XCTAssertEqual(executed, 3)
        XCTAssertFalse(interpolates)
    }

    @MainActor
    func testNaivePublishUsesTheLiveChannel() async {
        let pair = InMemoryTransport.makePair()
        let phone = PhoneSync(transport: pair.phone, mode: .naive)

        await phone.publish(Fixture.state())?.value

        let channels = pair.phone.sent.map(\.channel)
        XCTAssertEqual(channels, [.interactive])
    }

    @MainActor
    func testNaivePublishFailureIsCounted() async {
        let pair = InMemoryTransport.makePair(reachable: false)
        let phone = PhoneSync(transport: pair.phone, mode: .naive)

        await phone.publish(Fixture.state())?.value

        let failures = phone.publishFailures
        XCTAssertEqual(failures, 1)
    }

    // MARK: Replies and connect requests

    @MainActor
    func testOptimizedModeAcknowledgesInTheReply() async {
        let world = World(mode: .optimized)
        world.phone.publish(world.app.state)

        await world.watch.send(.play).value

        let replies = world.phoneTransport.sent.filter { $0.channel == .interactive }.map(\.message.kind)
        let roundTrip = world.watch.lastRoundTrip
        XCTAssertEqual(replies, [.state])
        XCTAssertEqual(roundTrip, 0)
    }

    @MainActor
    func testContextAckModeDoesNotReply() async {
        let world = World(mode: .contextAck)
        world.phone.publish(world.app.state)

        await world.watch.send(.play).value

        let replies = world.phoneTransport.sent.filter { $0.channel == .interactive }.count
        let acknowledged = world.watch.confirmedState.isPlaying
        XCTAssertEqual(replies, 0)
        XCTAssertTrue(acknowledged, "Acknowledged through the latest-value channel instead")
    }

    @MainActor
    func testWatchRequestsStateAndBookmarksWhenItConnects() async {
        let world = World()
        world.watchTransport.setReachable(false)
        let playing = Fixture.state(isPlaying: true)
        world.phone.publish(playing)
        world.phone.publishBookmarks(BookmarkList(episodeID: "glance", bookmarks: [Fixture.bookmark()]))

        world.watchTransport.setReachable(true)
        await world.watch.requestTask?.value

        let requests = world.watchTransport.sent.filter { $0.channel == .interactive }.map(\.message.payload)
        let replies = world.phoneTransport.sent.filter { $0.channel == .interactive }.map(\.message.kind)
        XCTAssertEqual(requests, [.request(.state), .request(.bookmarks)])
        XCTAssertEqual(replies, [.state, .bookmarks])
    }

    @MainActor
    func testRequestBeforeAnythingIsPublishedHasNoReply() {
        let pair = InMemoryTransport.makePair()
        let phone = PhoneSync(transport: pair.phone)
        let state = phone.reply(to: WireMessage(payload: .request(.state)))
        let bookmarks = phone.reply(to: WireMessage(payload: .request(.bookmarks)))
        let nonsense = phone.reply(to: WireMessage(payload: .request(.command)))
        XCTAssertNil(state)
        XCTAssertNil(bookmarks)
        XCTAssertNil(nonsense)
    }

    func testRequestRoundTripsThroughJSON() throws {
        let codec = MessageCodec()
        let message = WireMessage(payload: .request(.bookmarks), sentAt: Fixture.t0)
        let decoded = try codec.decode(codec.encode(message))
        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.kind, .request)
    }

    // MARK: Payload sizes

    /// Prints the encoded size of each message the apps send, as
    /// `WRISTCUE_PAYLOAD <name> <bytes>` lines for docs/PERFORMANCE.md. Dates
    /// have fractional seconds and IDs are random, like real traffic.
    func testReportPayloadSizes() throws {
        let codec = MessageCodec()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000.123456)
        let state = PlaybackState(
            episodeID: "glance",
            position: 41.876543,
            duration: 87.44,
            rate: 1,
            isPlaying: true,
            volume: 0.75,
            timestamp: now,
            lastCommandID: UUID()
        )
        func bookmark() -> Bookmark {
            Bookmark(episodeID: "glance", position: 41.876543, createdAt: now, source: .watch)
        }
        let samples: [(String, WireMessage.Payload)] = [
            ("state", .state(state)),
            ("command.play", .command(Command(issuedAt: now, action: .play))),
            ("command.skip", .command(Command(issuedAt: now, action: .skip(seconds: 30)))),
            ("command.setVolume", .command(Command(issuedAt: now, action: .setVolume(level: 0.75)))),
            ("command.addBookmark", .command(Command(issuedAt: now, action: .addBookmark(bookmark: bookmark())))),
            ("bookmarks.0", .bookmarks(BookmarkList(episodeID: "glance", bookmarks: []))),
            ("bookmarks.1", .bookmarks(BookmarkList(episodeID: "glance", bookmarks: [bookmark()]))),
            ("bookmarks.10", .bookmarks(BookmarkList(episodeID: "glance", bookmarks: (0..<10).map { _ in bookmark() }))),
        ]
        for (name, payload) in samples {
            let bytes = try codec.encode(WireMessage(payload: payload, sentAt: now)).count
            print("WRISTCUE_PAYLOAD \(name) \(bytes)")
            XCTAssertGreaterThan(bytes, 0)
        }
    }

    // MARK: Traffic model

    /// The same scripted minute in both modes, over the in-memory transport with a
    /// fake clock: play, 60 seconds of playback, one crown turn of 10 detents.
    /// Prints `WRISTCUE_TRAFFIC` lines. This counts what the sync logic hands to
    /// the transport; it is a model of the protocol, not a Simulator measurement.
    @MainActor
    func testReportTrafficForOneScriptedMinute() async {
        var totals: [SyncMode: Int] = [:]
        for mode in SyncMode.allCases {
            let world = World(mode: mode)
            world.watch.volumeDebounce = .seconds(3600)
            await world.phone.publish(world.app.state, sentAt: world.clock.now)?.value
            await world.watch.send(.play).value

            for second in 1...60 {
                world.advance(to: TimeInterval(second))
                if mode == .naive {
                    var live = world.app.state
                    live.position = live.estimatedPosition(at: world.clock.now)
                    live.timestamp = world.clock.now
                    await world.phone.publish(live, sentAt: world.clock.now)?.value
                }
            }

            for detent in 1...10 {
                await world.watch.setVolume(0.5 + Double(detent) * 0.05)?.value
            }
            await world.watch.flushVolume()?.value
            await world.app.waitForPublishes()

            let records = world.phoneTransport.sent + world.watchTransport.sent
            for channel in TransportChannel.allCases {
                let onChannel = records.filter { $0.channel == channel }
                print("WRISTCUE_TRAFFIC mode=\(mode.rawValue) channel=\(channel.rawValue) messages=\(onChannel.count) bytes=\(onChannel.reduce(0) { $0 + $1.byteCount })")
            }
            totals[mode] = records.count
        }
        let optimized = totals[.optimized] ?? 0
        let naive = totals[.naive] ?? 0
        XCTAssertLessThan(optimized, naive)
    }
}
