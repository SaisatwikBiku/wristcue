import SwiftUI
import WristCueKit

struct TransportControls: View {
    @Environment(PlayerModel.self) private var player
    // @ScaledMetric grows these sizes with the Dynamic Type setting.
    @ScaledMetric(relativeTo: .largeTitle) private var playSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title) private var skipSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 40) {
            Button {
                player.send(.skip(seconds: -RemoteCommandController.skipBackSeconds))
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: skipSize))
            }
            .accessibilityLabel("Skip back 15 seconds")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: playSize))
            }
            .accessibilityLabel(player.state.isPlaying ? "Pause" : "Play")

            Button {
                player.send(.skip(seconds: RemoteCommandController.skipForwardSeconds))
            } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: skipSize))
            }
            .accessibilityLabel("Skip forward 30 seconds")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}

struct VolumeControl: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
            Slider(
                value: Binding(get: { player.state.volume }, set: { player.send(.setVolume(level: $0)) }),
                in: 0...1
            )
            .accessibilityLabel("Volume")
            .accessibilityValue(player.state.volume.formatted(.percent.precision(.fractionLength(0))))
            Image(systemName: "speaker.wave.3.fill")
                .accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
    }
}
