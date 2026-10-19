import Foundation

/// Something the Watch asks the iPhone to do.
public struct Command: Codable, Hashable, Sendable, Identifiable {
    /// Created on the Watch. The iPhone echoes it back in `PlaybackState.lastCommandID`,
    /// which acknowledges delivery and lets the Watch time the round trip.
    public let id: UUID
    /// Watch clock time of the tap.
    public let issuedAt: Date
    public let action: Action

    public init(id: UUID = UUID(), issuedAt: Date = .now, action: Action) {
        self.id = id
        self.issuedAt = issuedAt
        self.action = action
    }

    /// An enum with associated values is Swift's sum type: each case carries only the
    /// data it needs, and `switch` must handle every case. Java would need a sealed
    /// interface and one class per case to get the same guarantee.
    public enum Action: Codable, Hashable, Sendable {
        case play
        case pause
        /// Relative jump. Negative skips back.
        case skip(seconds: TimeInterval)
        /// Absolute position in seconds.
        case seek(to: TimeInterval)
        /// Player volume from 0 to 1.
        case setVolume(level: Double)
        case addBookmark(bookmark: Bookmark)
    }
}

extension Command.Action {
    /// Groups of actions where only the newest one in a queue matters. Ten queued
    /// volume changes collapse to the last one, so a long offline stretch never
    /// replays a burst of stale commands.
    enum CoalescingGroup: Hashable {
        case transport
        case seek
        case volume
    }

    var coalescingGroup: CoalescingGroup? {
        switch self {
        case .play, .pause: return .transport
        case .seek: return .seek
        case .setVolume: return .volume
        // Skips add up, and each bookmark is a distinct moment, so neither collapses.
        case .skip, .addBookmark: return nil
        }
    }

    /// Durable actions must arrive however late. A bookmark saved offline is still
    /// worth keeping an hour later. A "pause" from an hour ago is not.
    var isDurable: Bool {
        switch self {
        case .addBookmark: return true
        case .play, .pause, .skip, .seek, .setVolume: return false
        }
    }
}
