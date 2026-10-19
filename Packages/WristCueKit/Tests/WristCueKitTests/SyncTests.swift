import XCTest
@testable import WristCueKit

/// Stands in for the iPhone app: runs commands with the kit's reducer and keeps
/// bookmarks in a BookmarkStore, the way PhoneCoordinator does.
@MainActor
private final class FakePhoneApp {
    var state = Fixture.state(isPlaying: false)
    var now = Fixture.t0
    var executed: [Command] = []
    /// When false, commands are recorded but never answered with a new state.
    var answers = true
    let bookmarks = BookmarkStore()
    var onChange: (@MainActor (PlaybackState) -> Void)?

    func perform(_ command: Command) {
        executed.append(command)
        if case .addBookmark(let bookmark) = command.action {
            bookmarks.add(bookmark)
        }
        guard answers else { return }
        state = state.applying(command, at: now)
        onChange?(state)
    }
}

@MainActor
private final class TestClock {
    var now = Fixture.t0
}

/// A phone and a watch joined by the in-memory transport.
@MainActor
private struct World {
    let phoneTransport: InMemoryTransport
    let watchTransport: InMemoryTransport
    let app: FakePhoneApp
    let clock: TestClock
    let phone: PhoneSync
    let watch: WatchSync

    init(queueStore: JSONFileStore<OfflineQueue>? = nil) {
        let pair = InMemoryTransport.makePair()
        let app = FakePhoneApp()
        let clock = TestClock()
        let phone = PhoneSync(transport: pair.phone)
        phone.onCommand = { command in
            app.perform(command)
        }
        app.onChange = { state in
            phone.publish(state, sentAt: clock.now)
        }
        app.bookmarks.onChange = {
            let episodeID = app.state.episodeID ?? ""
            phone.publishBookmarks(BookmarkList(episodeID: episodeID, bookmarks: app.bookmarks.bookmarks(for: episodeID)))
        }
        phoneTransport = pair.phone
        watchTransport = pair.watch
        self.app = app
        self.clock = clock
        self.phone = phone
        watch = WatchSync(transport: pair.watch, queueStore: queueStore, clock: { clock.now })
    }

    func advance(to seconds: TimeInterval) {
        clock.now = Fixture.t0.addingTimeInterval(seconds)
        app.now = clock.now
    }
}

/// A transport that is reachable but whose live sends always fail, for the
/// fallback path from a failed interactive send to the queue.
@MainActor
private final class FailingTransport: ConnectivityTransport {
    let isReachable = true
    var onReceive: (@MainActor (WireMessage) -> Void)?
    var onReachabilityChange: (@MainActor (Bool) -> Void)?
    var transferred: [WireMessage] = []

    func sendInteractive(_ message: WireMessage) async throws {
        throw TransportError.notReachable
    }

    func publishLatest(_ message: WireMessage) throws {}

    func transferGuaranteed(_ message: WireMessage) throws {
        transferred.append(message)
    }
}

private func temporaryQueueStore() -> JSONFileStore<OfflineQueue> {
    JSONFileStore(url: FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appending(path: "queue.json"))
}

/// Values are copied into locals before XCTAssert, whose autoclosures aren't
/// main-actor isolated.
final class SyncTests: XCTestCase {
    // MARK: Playback state and commands

    @MainActor
    func testWatchShowsStatePublishedByPhone() {
        let world = World()
        let published = Fixture.state(position: 20)

        world.phone.publish(published, sentAt: Fixture.t0)

        let display = world.watch.displayState
        let confirmed = world.watch.confirmedState
        XCTAssertEqual(display, published)
        XCTAssertEqual(confirmed, published)
    }

    @MainActor
    func testCommandRoundTripIsAcknowledged() async {
        let world = World()
        world.phone.publish(world.app.state)
        world.advance(to: 1)

        await world.watch.send(.play).value

        let executed = world.app.executed.map(\.action)
        let confirmedPlaying = world.watch.confirmedState.isPlaying
        let displayPlaying = world.watch.displayState.isPlaying
        let roundTrip = world.watch.lastRoundTrip
        let queued = world.watch.queuedCount
        XCTAssertEqual(executed, [.play])
        XCTAssertTrue(confirmedPlaying)
        XCTAssertTrue(displayPlaying)
        XCTAssertEqual(roundTrip, 0)
        XCTAssertEqual(queued, 0)
    }

    @MainActor
    func testDuplicateCommandRunsOnce() async throws {
        let world = World()
        let message = WireMessage(payload: .command(Fixture.command(.play)), sentAt: Fixture.t0)

        try await world.watchTransport.sendInteractive(message)
        try world.watchTransport.transferGuaranteed(message)

        let count = world.app.executed.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testGuessIsKeptUntilAcknowledgedOrTimedOut() async {
        let world = World()
        world.app.answers = false
        world.phone.publish(world.app.state, sentAt: Fixture.t0)

        await world.watch.send(.play).value
        let guessed = world.watch.displayState.isPlaying

        // A state that doesn't acknowledge the tap, inside the timeout: guess stays.
        world.advance(to: 1)
        world.phone.publish(world.app.state.applying(Fixture.command(.pause, id: 50), at: world.clock.now))
        let keptDuringTimeout = world.watch.displayState.isPlaying
        let confirmedDuringTimeout = world.watch.confirmedState.isPlaying

        // After the timeout, the iPhone's state wins.
        world.advance(to: 1 + WatchSync.acknowledgementTimeout + 1)
        world.phone.publish(world.app.state.applying(Fixture.command(.pause, id: 51), at: world.clock.now))
        let afterTimeout = world.watch.displayState.isPlaying

        XCTAssertTrue(guessed)
        XCTAssertTrue(keptDuringTimeout)
        XCTAssertFalse(confirmedDuringTimeout)
        XCTAssertFalse(afterTimeout)
    }

    @MainActor
    func testOlderStateNeverReplacesNewer() {
        let world = World()
        let newer = Fixture.state(position: 50)
        var older = Fixture.state(position: 10)
        older.timestamp = Fixture.t0.addingTimeInterval(-5)

        world.phone.publish(newer)
        world.phone.publish(older)

        let position = world.watch.confirmedState.position
        XCTAssertEqual(position, 50)
    }

    // MARK: Volume

    @MainActor
    func testCrownTurnsCollapseIntoOneVolumeCommand() async {
        let world = World()
        world.phone.publish(world.app.state)
        world.watch.volumeDebounce = .seconds(3600)

        world.watch.setVolume(0.2)
        world.watch.setVolume(0.6)
        let shownBeforeSend = world.watch.displayState.volume
        let sentBeforeFlush = world.app.executed.count
        await world.watch.flushVolume()?.value

        let executed = world.app.executed.map(\.action)
        XCTAssertEqual(shownBeforeSend, 0.6)
        XCTAssertEqual(sentBeforeFlush, 0)
        XCTAssertEqual(executed, [.setVolume(level: 0.6)])
    }

    @MainActor
    func testDebouncedVolumeIsSentAfterTheCrownRests() async throws {
        let world = World()
        world.phone.publish(world.app.state)
        world.watch.volumeDebounce = .milliseconds(10)

        world.watch.setVolume(0.3)
        try await Task.sleep(for: .milliseconds(200))

        let executed = world.app.executed.map(\.action)
        XCTAssertEqual(executed, [.setVolume(level: 0.3)])
    }

    @MainActor
    func testFlushWithNothingPendingSendsNothing() {
        let world = World()
        let task = world.watch.flushVolume()
        XCTAssertNil(task)
    }

    @MainActor
    func testNonFiniteVolumeIsIgnored() {
        let world = World()
        world.phone.publish(Fixture.state(volume: 0.5))
        world.watch.setVolume(.nan)
        let volume = world.watch.displayState.volume
        XCTAssertEqual(volume, 0.5)
    }

    // MARK: Offline queue

    @MainActor
    func testCommandsWaitWhileUnreachableThenFlushOnReconnect() async {
        let world = World()
        world.phone.publish(world.app.state)
        world.watchTransport.setReachable(false)

        await world.watch.send(.skip(seconds: 30)).value
        let queuedWhileAway = world.watch.queuedCount
        let shownWhileAway = world.watch.displayState.position
        let executedWhileAway = world.app.executed.count

        world.watchTransport.setReachable(true)

        let queuedAfter = world.watch.queuedCount
        let executed = world.app.executed.map(\.action)
        let reachable = world.watch.isReachable
        XCTAssertEqual(queuedWhileAway, 1)
        XCTAssertEqual(shownWhileAway, 40)
        XCTAssertEqual(executedWhileAway, 0)
        XCTAssertEqual(queuedAfter, 0)
        XCTAssertEqual(executed, [.skip(seconds: 30)])
        XCTAssertTrue(reachable)
    }

    @MainActor
    func testFailedLiveSendFallsBackToQueue() async {
        let transport = FailingTransport()
        let watch = WatchSync(transport: transport, clock: { Fixture.t0 })

        await watch.send(.play).value
        let queued = watch.queuedCount
        watch.flushQueue()

        let transferred = transport.transferred.map(\.kind)
        let queuedAfter = watch.queuedCount
        XCTAssertEqual(queued, 1)
        XCTAssertEqual(transferred, [.command])
        XCTAssertEqual(queuedAfter, 0)
    }

    @MainActor
    func testStalePlaybackCommandsExpireButBookmarksSurvive() async {
        let world = World()
        world.phone.publish(world.app.state)
        world.watchTransport.setReachable(false)

        await world.watch.addBookmark()?.value
        await world.watch.send(.pause).value
        world.advance(to: OfflineQueue.defaultMaxPlaybackCommandAge + 30)
        world.watchTransport.setReachable(true)

        let executed = world.app.executed.map(\.action)
        let stored = world.app.bookmarks.bookmarks.count
        XCTAssertEqual(executed.count, 1)
        if case .addBookmark = executed.first {} else {
            XCTFail("Expected only the bookmark to be delivered, got \(executed)")
        }
        XCTAssertEqual(stored, 1)
    }

    @MainActor
    func testQueueSurvivesRelaunch() async throws {
        let store = temporaryQueueStore()
        let first = World(queueStore: store)
        first.phone.publish(first.app.state)
        first.watchTransport.setReachable(false)
        await first.watch.addBookmark()?.value

        let saved = try store.load()?.pending.count
        // A new Watch app launch, still away from the iPhone.
        let relaunched = WatchSync(transport: InMemoryTransport.makePair(reachable: false).watch, queueStore: store)
        let restored = relaunched.queuedCount

        XCTAssertEqual(saved, 1)
        XCTAssertEqual(restored, 1)
    }

    @MainActor
    func testReachabilityIsMirrored() {
        let world = World()
        let before = world.watch.isReachable
        world.watchTransport.setReachable(false)
        let after = world.watch.isReachable
        XCTAssertTrue(before)
        XCTAssertFalse(after)
    }

    // MARK: Bookmarks

    @MainActor
    func testBookmarkCapturesTheMomentHeardNow() async {
        let world = World()
        world.phone.publish(Fixture.state(position: 10, isPlaying: true))
        world.advance(to: 5)

        await world.watch.addBookmark()?.value

        let positions = world.app.bookmarks.bookmarks.map(\.position)
        let sources = world.app.bookmarks.bookmarks.map(\.source)
        XCTAssertEqual(positions, [15])
        XCTAssertEqual(sources, [.watch])
    }

    @MainActor
    func testBookmarkIsPendingUntilPhoneListIncludesIt() async {
        let world = World()
        world.phone.publish(world.app.state)
        world.watchTransport.setReachable(false)

        await world.watch.addBookmark()?.value
        let whileAway = world.watch.bookmarkItems.map(\.isPending)

        world.watchTransport.setReachable(true)
        let afterSync = world.watch.bookmarkItems.map(\.isPending)

        XCTAssertEqual(whileAway, [true])
        XCTAssertEqual(afterSync, [false])
    }

    @MainActor
    func testBookmarkNeedsAnEpisode() {
        let world = World()
        let task = world.watch.addBookmark()
        let items = world.watch.bookmarkItems
        XCTAssertNil(task)
        XCTAssertTrue(items.isEmpty)
    }

    @MainActor
    func testOtherEpisodesBookmarksAreHidden() {
        let world = World()
        world.phone.publish(world.app.state)
        let other = Bookmark(episodeID: "crown", position: 5, createdAt: Fixture.t0, source: .phone)

        world.phone.publishBookmarks(BookmarkList(episodeID: "crown", bookmarks: [other]))

        let items = world.watch.bookmarkItems
        XCTAssertTrue(items.isEmpty)
    }

    @MainActor
    func testBookmarksAreListedInPlaybackOrder() {
        let world = World()
        world.phone.publish(world.app.state)
        let late = Fixture.bookmark(id: 1, position: 80)
        let early = Fixture.bookmark(id: 2, position: 20)

        world.phone.publishBookmarks(BookmarkList(episodeID: "glance", bookmarks: [late, early]))

        let positions = world.watch.bookmarkItems.map(\.bookmark.position)
        XCTAssertEqual(positions, [20, 80])
    }

    @MainActor
    func testEachSideIgnoresMessagesMeantForTheOther() async throws {
        let world = World()
        try world.watchTransport.publishLatest(WireMessage(payload: .state(Fixture.state()), sentAt: Fixture.t0))
        try await world.phoneTransport.sendInteractive(
            WireMessage(payload: .command(Fixture.command(.play)), sentAt: Fixture.t0)
        )

        let executed = world.app.executed.count
        let display = world.watch.displayState
        XCTAssertEqual(executed, 0)
        XCTAssertEqual(display, .idle)
    }
}
