import Foundation

/// Counts messages and bytes per channel and direction, for the M5 measurements.
///
/// Bytes are the encoded `WireMessage` JSON, the part this app controls.
/// WatchConnectivity's own framing on top of it isn't visible to apps and isn't
/// counted. For the latest-value channel, one send is one
/// `updateApplicationContext` call, and its bytes are every slot in the context,
/// because each call sends all of them.
public struct TrafficCounter: Sendable, Equatable {
    public enum Direction: String, Sendable, CaseIterable {
        case sent
        case received
    }

    public struct Tally: Sendable, Equatable {
        public var messages = 0
        public var bytes = 0

        public init(messages: Int = 0, bytes: Int = 0) {
            self.messages = messages
            self.bytes = bytes
        }
    }

    private struct Key: Hashable, Sendable {
        let channel: TransportChannel
        let direction: Direction
    }

    /// When counting started, for per-minute rates.
    public private(set) var startedAt: Date
    private var tallies: [Key: Tally] = [:]

    public init(startedAt: Date = .now) {
        self.startedAt = startedAt
    }

    public mutating func record(_ channel: TransportChannel, _ direction: Direction, bytes: Int) {
        tallies[Key(channel: channel, direction: direction), default: Tally()].messages += 1
        tallies[Key(channel: channel, direction: direction), default: Tally()].bytes += bytes
    }

    public mutating func reset(at date: Date = .now) {
        tallies.removeAll()
        startedAt = date
    }

    public func tally(_ channel: TransportChannel, _ direction: Direction) -> Tally {
        tallies[Key(channel: channel, direction: direction)] ?? Tally()
    }

    /// All channels together, one direction.
    public func total(_ direction: Direction) -> Tally {
        TransportChannel.allCases.reduce(into: Tally()) { sum, channel in
            let tally = tally(channel, direction)
            sum.messages += tally.messages
            sum.bytes += tally.bytes
        }
    }

    /// `count` scaled to one minute of the time since `startedAt`. Nil before a
    /// full second has passed, when the rate would mostly be noise.
    public func perMinute(_ count: Int, now: Date = .now) -> Double? {
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed >= 1 else { return nil }
        return Double(count) / elapsed * 60
    }
}

/// A transport that keeps a `TrafficCounter`. The diagnostics screens read it.
@MainActor
public protocol TrafficCounting: AnyObject {
    var traffic: TrafficCounter { get }
    func resetTraffic()
}
