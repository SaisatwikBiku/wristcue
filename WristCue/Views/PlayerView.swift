import SwiftUI
import WristCueKit

struct PlayerView: View {
    let episode: Episode
    @Environment(PlayerModel.self) private var player

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(episode.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(episode.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let error = player.loadError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if player.currentEpisode == episode {
                    ScrubberView()
                    TransportControls()
                    VolumeControl()
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            player.select(episode)
        }
    }
}
