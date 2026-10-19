import XCTest
@testable import WristCueKit

final class CommandApplyingTests: XCTestCase {
    private let t0 = Fixture.t0

    func testEveryCommandStampsTimeAndCommandID() {
        let command = Fixture.command(.pause, id: 7)
        let next = Fixture.state().applying(command, at: t0.addingTimeInterval(3))
        XCTAssertEqual(next.lastCommandID, Fixture.uuid(7))
        XCTAssertEqual(next.timestamp, t0.addingTimeInterval(3))
    }

    func testPlayStartsPlayback() {
        let next = Fixture.state(isPlaying: false).applying(Fixture.command(.play), at: t0)
        XCTAssertTrue(next.isPlaying)
        XCTAssertEqual(next.position, 10)
    }

    func testPlayWithNothingLoadedDoesNothing() {
        let next = PlaybackState.idle.applying(Fixture.command(.play), at: t0)
        XCTAssertFalse(next.isPlaying)
    }

    func testPlayAtEndRestartsFromBeginning() {
        let next = Fixture.state(position: 100, duration: 100).applying(Fixture.command(.play), at: t0)
        XCTAssertTrue(next.isPlaying)
        XCTAssertEqual(next.position, 0)
    }

    func testPauseFreezesTheInterpolatedPosition() {
        let playing = Fixture.state(position: 10, isPlaying: true)
        let next = playing.applying(Fixture.command(.pause), at: t0.addingTimeInterval(5))
        XCTAssertFalse(next.isPlaying)
        XCTAssertEqual(next.position, 15, accuracy: 1e-9)
    }

    func testSkipForwardFromWhereTheListenerIs() {
        let playing = Fixture.state(position: 10, isPlaying: true)
        let next = playing.applying(Fixture.command(.skip(seconds: 30)), at: t0.addingTimeInterval(5))
        XCTAssertEqual(next.position, 45, accuracy: 1e-9)
        XCTAssertTrue(next.isPlaying)
    }

    func testSkipBackStopsAtZero() {
        let next = Fixture.state(position: 10).applying(Fixture.command(.skip(seconds: -15)), at: t0)
        XCTAssertEqual(next.position, 0)
    }

    func testSkipForwardStopsAtDuration() {
        let next = Fixture.state(position: 90).applying(Fixture.command(.skip(seconds: 30)), at: t0)
        XCTAssertEqual(next.position, 100)
    }

    func testSeekIsClampedToEpisode() {
        let state = Fixture.state()
        XCTAssertEqual(state.applying(Fixture.command(.seek(to: 61.5)), at: t0).position, 61.5)
        XCTAssertEqual(state.applying(Fixture.command(.seek(to: 250)), at: t0).position, 100)
        XCTAssertEqual(state.applying(Fixture.command(.seek(to: -5)), at: t0).position, 0)
    }

    func testNonFiniteSeekKeepsPosition() {
        let state = Fixture.state(position: 10)
        XCTAssertEqual(state.applying(Fixture.command(.seek(to: .nan)), at: t0).position, 10)
        XCTAssertEqual(state.applying(Fixture.command(.skip(seconds: .infinity)), at: t0).position, 10)
    }

    func testVolumeIsClampedToUnitRange() {
        let state = Fixture.state(volume: 0.5)
        XCTAssertEqual(state.applying(Fixture.command(.setVolume(level: 0.8)), at: t0).volume, 0.8)
        XCTAssertEqual(state.applying(Fixture.command(.setVolume(level: 1.4)), at: t0).volume, 1)
        XCTAssertEqual(state.applying(Fixture.command(.setVolume(level: -0.2)), at: t0).volume, 0)
        XCTAssertEqual(state.applying(Fixture.command(.setVolume(level: .nan)), at: t0).volume, 0.5)
    }

    func testBookmarkDoesNotChangePlayback() {
        let state = Fixture.state(position: 10, isPlaying: false, volume: 0.5)
        let next = state.applying(Fixture.command(.addBookmark(bookmark: Fixture.bookmark())), at: t0)
        XCTAssertEqual(next.position, state.position)
        XCTAssertEqual(next.isPlaying, state.isPlaying)
        XCTAssertEqual(next.volume, state.volume)
        XCTAssertEqual(next.episodeID, state.episodeID)
    }

    func testOnlyBookmarksAreDurable() {
        XCTAssertTrue(Command.Action.addBookmark(bookmark: Fixture.bookmark()).isDurable)
        let others: [Command.Action] = [.play, .pause, .skip(seconds: 30), .seek(to: 1), .setVolume(level: 1)]
        XCTAssertTrue(others.allSatisfy { !$0.isDurable })
    }
}
