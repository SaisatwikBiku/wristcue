import Foundation

/// Median and 95th percentile of round-trip samples.
///
/// The median is the middle sample, or the mean of the two middle samples for an
/// even count. The 95th percentile uses the nearest-rank method: the sample at
/// rank ceil(0.95 * n) in ascending order. Nearest rank always reports a value
/// that was actually measured, never an interpolated one.
public struct LatencySummary: Sendable, Equatable {
    public let count: Int
    public let median: TimeInterval
    public let p95: TimeInterval
    public let min: TimeInterval
    public let max: TimeInterval

    /// Nil when there are no samples.
    public init?(samples: [TimeInterval]) {
        let sorted = samples.filter(\.isFinite).sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let n = sorted.count
        count = n
        min = first
        max = last
        median = n.isMultiple(of: 2) ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[n / 2]
        let rank = Int((0.95 * Double(n)).rounded(.up))
        p95 = sorted[rank - 1]
    }
}
