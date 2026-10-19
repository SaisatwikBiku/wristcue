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
                    BookmarkButton(episode: episode)
                    #if DEBUG
                    NowPlayingDebugView()
                    #endif
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

/// Saves the moment heard now. The label changes for a moment so the save is
/// visible, not only implied.
private struct BookmarkButton: View {
    let episode: Episode
    @Environment(PlayerModel.self) private var player
    @Environment(BookmarkStore.self) private var store
    @State private var justSaved = false

    var body: some View {
        Button {
            store.add(Bookmark(episodeID: episode.id, position: player.currentPosition(), source: .phone))
            justSaved = true
        } label: {
            Label(
                justSaved ? "Saved" : "Bookmark this moment",
                systemImage: justSaved ? "checkmark" : "bookmark"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .sensoryFeedback(.success, trigger: justSaved) { _, saved in saved }
        .task(id: justSaved) {
            guard justSaved else { return }
            try? await Task.sleep(for: .seconds(1.5))
            justSaved = false
        }
    }
}
