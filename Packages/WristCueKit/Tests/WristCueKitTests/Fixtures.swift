import Foundation
@testable import WristCueKit

/// Deterministic test data. Dates are whole seconds so they survive JSON exactly,
/// and UUIDs are readable so a failing assertion shows which command it was.
enum Fixture {
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func uuid(_ number: Int) -> UUID {
        let digits = String(number)
        let padded = String(repeating: "0", count: 12 - digits.count) + digits
        return UUID(uuidString: "00000000-0000-0000-0000-\(padded)")!
    }

    static func state(
        position: TimeInterval = 10,
        duration: TimeInterval = 100,
        rate: Double = 1,
        isPlaying: Bool = false,
        volume: Double = 0.5
    ) -> PlaybackState {
        PlaybackState(
            episodeID: "glance",
            position: position,
            duration: duration,
            rate: rate,
            isPlaying: isPlaying,
            volume: volume,
            timestamp: t0
        )
    }

    static func command(_ action: Command.Action, id: Int = 1, secondsAfterT0: TimeInterval = 0) -> Command {
        Command(id: uuid(id), issuedAt: t0.addingTimeInterval(secondsAfterT0), action: action)
    }

    static func bookmark(id: Int = 100, position: TimeInterval = 42) -> Bookmark {
        Bookmark(id: uuid(id), episodeID: "glance", position: position, createdAt: t0, source: .watch)
    }
}
