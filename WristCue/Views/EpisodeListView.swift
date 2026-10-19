import SwiftUI
import WristCueKit

/// Screens the list can push.
enum Route: Hashable {
    case player(Episode)
    case bookmarks
}

struct EpisodeListView: View {
    @Environment(PlayerModel.self) private var player
    /// Owned here so the bookmarks screen can replace itself with the player.
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            List(player.episodes) { episode in
                NavigationLink(value: Route.player(episode)) {
                    EpisodeRow(
                        episode: episode,
                        isCurrent: episode == player.currentEpisode,
                        isPlaying: episode == player.currentEpisode && player.state.isPlaying
                    )
                }
            }
            .navigationTitle("WristCue")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.bookmarks) {
                        Label("Bookmarks", systemImage: "bookmark")
                    }
                }
            }
            // Value-based navigation: the list pushes a Route, and this closure
            // decides which screen shows it.
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .player(let episode):
                    PlayerView(episode: episode)
                case .bookmarks:
                    BookmarksView { episode in
                        path = [.player(episode)]
                    }
                }
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                Text(episode.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        // One VoiceOver element per row, which states whether it's playing.
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? (isPlaying ? "Playing" : "Paused") : "")
        .accessibilityHint("Opens the player")
    }
}
