import Foundation

/// Three ways to keep the Watch in step, so their cost can be measured side by side.
///
/// - `optimized` is the design the app ships with: the iPhone publishes state only
///   when it changes, on the latest-value channel; the Watch interpolates progress
///   locally and debounces crown turns; and the iPhone answers each command from
///   the Watch with its new state in the live message's reply.
/// - `contextAck` is the first M5 design: the same, except that commands are
///   acknowledged only through the latest-value channel. Measured at about 1.7 s
///   per round trip in the Simulator, which is why `optimized` replaced it.
/// - `naive` is the first version most people would write: the iPhone sends its
///   state as a live message every second while playing and on every change, the
///   Watch draws whatever position arrived last, and every crown detent sends a
///   volume command.
///
/// Both modes use the same command path (live message, offline queue), so a
/// latency comparison measures the same thing in each.
public enum SyncMode: String, Sendable, CaseIterable {
    case optimized
    case contextAck
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
