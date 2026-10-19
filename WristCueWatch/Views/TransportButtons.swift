import SwiftUI
import WristCueKit

/// Back 15, play/pause, forward 30. Three is the most that fit across a watch
/// screen at a size a fingertip can hit reliably.
struct TransportButtons: View {
    @Environment(WatchSync.self) private var sync

    var body: some View {
        let isPlaying = sync.displayState.isPlaying
        HStack(spacing: 6) {
            Button {
                act(.skip(seconds: -15))
            } label: {
                Image(systemName: "gobackward.15")
            }
            .accessibilityLabel("Skip back 15 seconds")

            Button {
                act(isPlaying ? .pause : .play)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityHint("Controls playback on your iPhone")

            Button {
                act(.skip(seconds: 30))
            } label: {
                Image(systemName: "goforward.30")
            }
            .accessibilityLabel("Skip forward 30 seconds")
        }
        .disabled(sync.displayState.episodeID == nil)
    }

    private func act(_ action: Command.Action) {
        Haptics.play(for: action)
        sync.send(action)
    }
}
