import XCTest
@testable import WristCueKit

final class InterpolationTests: XCTestCase {
    private let t0 = Fixture.t0

    func testPausedStateDoesNotMove() {
        let state = Fixture.state(position: 10, isPlaying: false)
        XCTAssertEqual(state.estimatedPosition(at: t0.addingTimeInterval(60)), 10)
    }

    func testPlayingStateAdvancesWithElapsedTime() {
        let state = Fixture.state(position: 10, isPlaying: true)
        XCTAssertEqual(state.estimatedPosition(at: t0.addingTimeInterval(5)), 15, accuracy: 1e-9)
    }

    func testRateScalesElapsedTime() {
        let state = Fixture.state(position: 10, rate: 1.5, isPlaying: true)
        XCTAssertEqual(state.estimatedPosition(at: t0.addingTimeInterval(4)), 16, accuracy: 1e-9)
    }

    func testZeroRateDoesNotMove() {
        let state = Fixture.state(position: 10, rate: 0, isPlaying: true)
        XCTAssertEqual(state.estimatedPosition(at: t0.addingTimeInterval(30)), 10)
    }

    func testClampsToDuration() {
        let state = Fixture.state(position: 90, duration: 100, isPlaying: true)
        XCTAssertEqual(state.estimatedPosition(at: t0.addingTimeInterval(500)), 100)
    }

    func testWatchClockBehindPhoneClockDoesNotMoveBackwards() {
        let state = Fixture.state(position: 10, isPlaying: true)
        XCTAssertEqual(state.estimatedPosition(at: t0.addingTimeInterval(-3)), 10)
    }

    func testUnknownDurationOnlyClampsAtZero() {
        let state = Fixture.state(position: 10, duration: 0, isPlaying: true)
        XCTAssertEqual(state.estimatedPosition(at: t0.addingTimeInterval(500)), 510, accuracy: 1e-9)
    }

    func testProgressIsFractionOfDuration() {
        let state = Fixture.state(position: 20, duration: 80, isPlaying: true)
        XCTAssertEqual(state.progress(at: t0.addingTimeInterval(20)), 0.5, accuracy: 1e-9)
    }

    func testProgressIsZeroWhenDurationUnknown() {
        let state = Fixture.state(position: 20, duration: 0)
        XCTAssertEqual(state.progress(at: t0), 0)
    }

    func testIdleStateSitsAtZero() {
        XCTAssertNil(PlaybackState.idle.episodeID)
        XCTAssertEqual(PlaybackState.idle.estimatedPosition(at: t0), 0)
    }
}
