import SwiftUI
import WristCueKit

/// Progress bar and times, computed on the Watch from the last state.
///
/// How often it redraws is the main power decision on this screen:
/// - playing, screen awake: at most once a second;
/// - wrist down (always-on, `isLuminanceReduced`): once a minute, showing minutes
///   only, because seconds would be wrong for most of that minute;
/// - paused or app in the background: not at all.
struct ProgressRow: View {
    let state: PlaybackState
    let isLuminanceReduced: Bool
    let isInBackground: Bool

    var body: some View {
        TimelineView(.animation(
            minimumInterval: isLuminanceReduced ? 60 : 1,
            paused: !state.isPlaying || isInBackground
        )) { context in
            let position = state.estimatedPosition(at: context.date)
            let remaining = max(state.duration - position, 0)
            VStack(spacing: 2) {
                ProgressView(value: state.duration > 0 ? position / state.duration : 0)
                    .accessibilityLabel("Progress")
                    .accessibilityValue("\(TimeFormat.spoken(position)) of \(TimeFormat.spoken(state.duration))")
                if isLuminanceReduced {
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
}
