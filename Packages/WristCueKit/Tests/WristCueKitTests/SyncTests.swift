import XCTest
@testable import WristCueKit

/// Stands in for the iPhone's PlayerModel: runs commands with the kit's reducer.
@MainActor
private final class FakePlayer {
    var state = Fixture.state(isPlaying: false)
    var now = Fixture.t0
    var executed: [Command] = []
    /// When false, commands are recorded but never answered with a new state.
    var answers = true
    var onChange: (@MainActor (PlaybackState) -> Void)?

    func perform(_ command: Command) {
        executed.append(command)
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
    let player: FakePlayer
    let clock: TestClock
    let phone: PhoneSync
    let watch: WatchSync

    init() {
        let pair = InMemoryTransport.makePair()
        let player = FakePlayer()
        let clock = TestClock()
        let phone = PhoneSync(transport: pair.phone) { command in
            player.perform(command)
        }
        player.onChange = { state in
            phone.publish(state, sentAt: clock.now)
        }
        phoneTransport = pair.phone
        watchTransport = pair.watch
        self.player = player
        self.clock = clock
        self.phone = phone
        watch = WatchSync(transport: pair.watch, clock: { clock.now })
    }

    func advance(to seconds: TimeInterval) {
        clock.now = Fixture.t0.addingTimeInterval(seconds)
        player.now = clock.now
    }
}

/// Values are copied into locals before XCTAssert, whose autoclosures aren't
/// main-actor isolated.
final class SyncTests: XCTestCase {
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
        world.phone.publish(world.player.state)
        world.advance(to: 1)

        await world.watch.send(.play).value

        let executed = world.player.executed.map(\.action)
        let confirmedPlaying = world.watch.confirmedState.isPlaying
        let displayPlaying = world.watch.displayState.isPlaying
        let roundTrip = world.watch.lastRoundTrip
        let failed = world.watch.lastSendFailed
        XCTAssertEqual(executed, [.play])
        XCTAssertTrue(confirmedPlaying)
        XCTAssertTrue(displayPlaying)
        XCTAssertEqual(roundTrip, 0)
        XCTAssertFalse(failed)
    }

    @MainActor
    func testDuplicateCommandRunsOnce() async throws {
        let world = World()
        let message = WireMessage(payload: .command(Fixture.command(.play)), sentAt: Fixture.t0)

        try await world.watchTransport.sendInteractive(message)
        try await world.watchTransport.sendInteractive(message)

        let count = world.player.executed.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testFailedSendRevertsToConfirmedState() async {
        let world = World()
        world.phone.publish(world.player.state)
        world.watchTransport.setReachable(false)

        await world.watch.send(.play).value

        let failed = world.watch.lastSendFailed
        let display = world.watch.displayState
        let confirmed = world.watch.confirmedState
        let executed = world.player.executed.count
        XCTAssertTrue(failed)
        XCTAssertEqual(display, confirmed)
        XCTAssertFalse(display.isPlaying)
        XCTAssertEqual(executed, 0)
    }

    @MainActor
    func testGuessIsKeptUntilAcknowledgedOrTimedOut() async {
        let world = World()
        world.player.answers = false
        world.phone.publish(world.player.state, sentAt: Fixture.t0)

        await world.watch.send(.play).value
        let guessed = world.watch.displayState.isPlaying

        // A state that doesn't acknowledge the tap, inside the timeout: guess stays.
        world.advance(to: 1)
        world.phone.publish(world.player.state.applying(Fixture.command(.pause, id: 50), at: world.clock.now))
        let keptDuringTimeout = world.watch.displayState.isPlaying
        let confirmedDuringTimeout = world.watch.confirmedState.isPlaying

        // After the timeout, the iPhone's state wins.
        world.advance(to: 1 + WatchSync.acknowledgementTimeout + 1)
        world.phone.publish(world.player.state.applying(Fixture.command(.pause, id: 51), at: world.clock.now))
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

    @MainActor
    func testCrownTurnsCollapseIntoOneVolumeCommand() async {
        let world = World()
        world.phone.publish(world.player.state)
        world.watch.volumeDebounce = .seconds(3600)

        world.watch.setVolume(0.2)
        world.watch.setVolume(0.6)
        let shownBeforeSend = world.watch.displayState.volume
        let sentBeforeFlush = world.player.executed.count
        await world.watch.flushVolume()?.value

        let executed = world.player.executed.map(\.action)
        XCTAssertEqual(shownBeforeSend, 0.6)
        XCTAssertEqual(sentBeforeFlush, 0)
        XCTAssertEqual(executed, [.setVolume(level: 0.6)])
    }

    @MainActor
    func testDebouncedVolumeIsSentAfterTheCrownRests() async throws {
        let world = World()
        world.phone.publish(world.player.state)
        world.watch.volumeDebounce = .milliseconds(10)

        world.watch.setVolume(0.3)
        try await Task.sleep(for: .milliseconds(200))

        let executed = world.player.executed.map(\.action)
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

    @MainActor
    func testReachabilityIsMirrored() {
        let world = World()
        let before = world.watch.isReachable
        world.watchTransport.setReachable(false)
        let after = world.watch.isReachable
        XCTAssertTrue(before)
        XCTAssertFalse(after)
    }

    @MainActor
    func testEachSideIgnoresMessagesMeantForTheOther() async throws {
        let world = World()
        // A state sent to the phone is not a command.
        try world.watchTransport.publishLatest(WireMessage(payload: .state(Fixture.state()), sentAt: Fixture.t0))
        // A command sent to the watch is not a state.
        try await world.phoneTransport.sendInteractive(
            WireMessage(payload: .command(Fixture.command(.play)), sentAt: Fixture.t0)
        )

        let executed = world.player.executed.count
        let display = world.watch.displayState
        XCTAssertEqual(executed, 0)
        XCTAssertEqual(display, .idle)
    }
}
