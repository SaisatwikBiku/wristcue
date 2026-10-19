import Foundation

/// Two ways to keep the Watch in step, so their cost can be measured side by side.
///
/// - `optimized` is the design the app ships with: the iPhone publishes state only
///   when it changes, on the latest-value channel; the Watch interpolates progress
///   locally and debounces crown turns.
/// - `naive` is the first version most people would write: the iPhone sends its
///   state as a live message every second while playing and on every change, the
///   Watch draws whatever position arrived last, and every crown detent sends a
///   volume command.
///
/// Both modes use the same command path (live message, offline queue), so a
/// latency comparison measures the same thing in each.
public enum SyncMode: String, Sendable, CaseIterable {
    case optimized
    case naive

    /// The launch argument that picks the mode, for example
    /// `xcrun simctl launch <device> <bundle id> -WristCueSyncMode naive`.
    /// Launch arguments of the form `-key value` land in UserDefaults.
    public static let defaultsKey = "WristCueSyncMode"

    /// How often the iPhone sends its state in naive mode while playing.
    public static let naiveTickInterval: Duration = .seconds(1)

    /// The mode from launch arguments, `optimized` when none or an unknown one is given.
    public static func fromDefaults(_ defaults: UserDefaults = .standard) -> SyncMode {
        defaults.string(forKey: defaultsKey).flatMap(SyncMode.init(rawValue:)) ?? .optimized
    }
}
