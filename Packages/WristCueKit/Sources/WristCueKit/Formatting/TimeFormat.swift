import Foundation

/// Time strings shared by both apps, so the iPhone and the Watch show and speak
/// positions the same way.
public enum TimeFormat {
    /// "1:05" style, for on-screen labels.
    public static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(sanitized(seconds)).formatted(.time(pattern: .minuteSecond))
    }

    /// "1 minute, 5 seconds" style, for VoiceOver. A screen reader would read
    /// "1:05" as "one colon zero five".
    public static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(sanitized(seconds)).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    /// Negative and non-finite values show as zero instead of trapping.
    static func sanitized(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? max(0, seconds) : 0
    }
}
