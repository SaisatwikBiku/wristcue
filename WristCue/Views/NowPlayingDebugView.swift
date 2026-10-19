#if DEBUG
import MediaPlayer
import SwiftUI

/// Debug builds only: shows what the app last published to MPNowPlayingInfoCenter.
///
/// The iOS Simulator doesn't reliably draw the Lock Screen or Control Center
/// player, so this confirms the app side of the Now Playing integration without
/// it. The elapsed time only changes when the app publishes a new state (play,
/// pause, seek), because the system animates the bar from elapsed time and rate.
struct NowPlayingDebugView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            VStack(alignment: .leading, spacing: 4) {
                Text("Now Playing info (debug)")
                    .font(.caption.bold())
                Text("Title: \(info[MPMediaItemPropertyTitle] as? String ?? "none")")
                Text("Elapsed at last update: \(seconds(info[MPNowPlayingInfoPropertyElapsedPlaybackTime]))")
                Text("Duration: \(seconds(info[MPMediaItemPropertyPlaybackDuration]))")
                Text("Rate: \(seconds(info[MPNowPlayingInfoPropertyPlaybackRate]))")
            }
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
    }

    private func seconds(_ value: Any?) -> String {
        guard let number = value as? Double else { return "none" }
        return number.formatted(.number.precision(.fractionLength(1)))
    }
}
#endif
