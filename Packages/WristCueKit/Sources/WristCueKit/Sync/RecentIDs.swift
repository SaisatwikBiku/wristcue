import Foundation

/// A set that remembers only the most recent `capacity` IDs.
///
/// Used to drop duplicates: the same command can arrive twice when an interactive
/// send times out after it was actually delivered and the Watch falls back to a
/// guaranteed transfer. Remembering every ID forever would grow without limit, and
/// a duplicate arrives within seconds or minutes, so a bounded window is enough.
public struct RecentIDs<ID: Hashable & Codable & Sendable>: Codable, Sendable {
    public let capacity: Int
    // The array keeps insertion order for eviction. The set makes `contains` O(1).
    private var order: [ID] = []
    private var members: Set<ID> = []

    public init(capacity: Int) {
        precondition(capacity > 0, "RecentIDs needs room for at least one ID")
        self.capacity = capacity
    }

    public var count: Int { order.count }

    public func contains(_ id: ID) -> Bool {
        members.contains(id)
    }

    /// Adds `id`. Returns false if it was already present.
    @discardableResult
    public mutating func insert(_ id: ID) -> Bool {
        guard members.insert(id).inserted else { return false }
        order.append(id)
        if order.count > capacity {
            members.remove(order.removeFirst())
        }
        return true
    }
}
