import Foundation

/// Commands waiting to reach the iPhone, kept on the Watch while it's unreachable.
///
/// Bookmarks travel as `addBookmark` commands, so one queue covers both. The queue:
/// - keeps first-in, first-out order,
/// - drops a command whose ID it has already queued or settled (de-duplication),
/// - collapses commands where only the newest matters (volume, play/pause, seek),
/// - expires stale playback commands but never bookmarks.
///
/// It's a value type with no I/O. The Watch coordinator decides when to persist it
/// (it's Codable) and when to send, which keeps this logic testable.
public struct OfflineQueue: Codable, Sendable {
    public enum EnqueueResult: Equatable, Sendable {
        case queued
        /// The ID was already queued or already settled. Nothing changed.
        case duplicate
        /// Queued, and an older command in the same group was removed.
        case replaced(Command.ID)
    }

    public static let defaultMaxPlaybackCommandAge: TimeInterval = 30

    public private(set) var pending: [Command] = []
    /// How old a non-bookmark command can be before it's dropped. A design choice
    /// (30 s by default), not a measurement: a skip that lands half a minute after
    /// the tap is more confusing than one that never happens.
    public let maxPlaybackCommandAge: TimeInterval
    /// IDs that left the queue (delivered, replaced or expired), so a late duplicate
    /// is recognized.
    private var settled: RecentIDs<Command.ID>

    public init(
        maxPlaybackCommandAge: TimeInterval = OfflineQueue.defaultMaxPlaybackCommandAge,
        rememberedIDs: Int = 256
    ) {
        self.maxPlaybackCommandAge = maxPlaybackCommandAge
        settled = RecentIDs(capacity: rememberedIDs)
    }

    public var isEmpty: Bool { pending.isEmpty }

    @discardableResult
    public mutating func enqueue(_ command: Command) -> EnqueueResult {
        guard !settled.contains(command.id), !pending.contains(where: { $0.id == command.id }) else {
            return .duplicate
        }
        var result = EnqueueResult.queued
        // Coalescing keeps at most one pending command per group, so there is never
        // more than one to replace.
        if let group = command.action.coalescingGroup,
           let index = pending.firstIndex(where: { $0.action.coalescingGroup == group }) {
            let replaced = pending.remove(at: index)
            settled.insert(replaced.id)
            result = .replaced(replaced.id)
        }
        pending.append(command)
        return result
    }

    /// Removes commands the iPhone has confirmed.
    public mutating func markDelivered(_ ids: [Command.ID]) {
        let delivered = Set(ids)
        pending.removeAll { delivered.contains($0.id) }
        for id in ids {
            settled.insert(id)
        }
    }

    /// Drops non-durable commands older than `maxPlaybackCommandAge` and returns them.
    @discardableResult
    public mutating func removeExpired(now: Date) -> [Command] {
        let expired = pending.filter {
            !$0.action.isDurable && now.timeIntervalSince($0.issuedAt) > maxPlaybackCommandAge
        }
        markDelivered(expired.map(\.id))
        return expired
    }
}
