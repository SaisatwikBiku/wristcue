import SwiftUI
import WristCueKit

/// Progress bar and times.
///
/// In optimized mode the position is computed on the Watch from the last state,
/// and how often it redraws is the main power decision on this screen:
/// - playing, screen awake: at most once a second;
/// - wrist down (always-on, `isLuminanceReduced`): once a minute, showing minutes
///   only, because seconds would be wrong for most of that minute;
/// - paused or app in the background: not at all.
///
/// In naive mode it shows the position of the last state that arrived, so it
/// redraws when, and only when, the iPhone's once-a-second message lands.
struct ProgressRow: View {
    let state: PlaybackState
    let interpolates: Bool
    let isLuminanceReduced: Bool
    let isInBackground: Bool

    var body: some View {
        if interpolates {
            TimelineView(.animation(
                minimumInterval: isLuminanceReduced ? 60 : 1,
                paused: !state.isPlaying || isInBackground
            )) { context in
                ProgressContent(
                    position: state.estimatedPosition(at: context.date),
                    duration: state.duration,
                    showsMinutesOnly: isLuminanceReduced
                )
            }
        } else {
            ProgressContent(position: state.position, duration: state.duration, showsMinutesOnly: isLuminanceReduced)
        }
    }
}

private struct ProgressContent: View {
    let position: TimeInterval
    let duration: TimeInterval
    let showsMinutesOnly: Bool

    var body: some View {
        let remaining = max(duration - position, 0)
        VStack(spacing: 2) {
            ProgressView(value: duration > 0 ? min(position / duration, 1) : 0)
                .accessibilityLabel("Progress")
                .accessibilityValue("\(TimeFormat.spoken(position)) of \(TimeFormat.spoken(duration))")
            if showsMinutesOnly {
                Text("\(Int((remaining / 60).rounded(.up))) min left")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                HStack {
                    Text(TimeFormat.clock(position))
                    Spacer()
                    Text("-\(TimeFormat.clock(remaining))")
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
    }
}
