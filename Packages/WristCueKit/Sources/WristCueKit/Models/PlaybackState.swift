import Foundation

/// A snapshot of the iPhone player at one instant.
///
/// The Watch never receives a stream of positions. It receives one snapshot and
/// computes the current position itself (see PlaybackState+Interpolation.swift).
/// This is a struct, so every copy is independent and the type is safe to pass
/// between threads, which is why it can be `Sendable` with no locks.
public struct PlaybackState: Codable, Hashable, Sendable {
    public var episodeID: Episode.ID?
    /// Seconds from the start of the episode at `timestamp`.
    public var position: TimeInterval
    /// Episode length in seconds as reported by the player, or 0 if unknown.
    public var duration: TimeInterval
    /// Playback speed. 1 is normal speed.
    public var rate: Double
    public var isPlaying: Bool
    /// Player volume from 0 to 1.
    public var volume: Double
    /// When `position` was sampled, on the iPhone's clock.
    public var timestamp: Date
    /// The most recent Watch command this state reflects, if any.
    public var lastCommandID: Command.ID?

    public init(
        episodeID: Episode.ID? = nil,
        position: TimeInterval = 0,
        duration: TimeInterval = 0,
        rate: Double = 1,
        isPlaying: Bool = false,
        volume: Double = 1,
        timestamp: Date,
        lastCommandID: Command.ID? = nil
    ) {
        self.episodeID = episodeID
        self.position = position
        self.duration = duration
        self.rate = rate
        self.isPlaying = isPlaying
        self.volume = volume
        self.timestamp = timestamp
        self.lastCommandID = lastCommandID
    }

    /// Nothing loaded. Used before the first state arrives.
    public static let idle = PlaybackState(timestamp: .distantPast)

    /// Keeps a position inside the episode. A non-finite input leaves the current
    /// position unchanged, so a corrupt command can't produce NaN on screen.
    func clampedPosition(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return position }
        let upperBound = duration > 0 ? duration : .infinity
        return min(max(value, 0), upperBound)
    }
}
