import SwiftUI
import WristCueKit

/// Every bookmark, grouped by episode in library order. Tap to play from that
/// moment, swipe to delete.
struct BookmarksView: View {
    /// Shows the player for the episode a tapped bookmark belongs to.
    let showPlayer: (Episode) -> Void
    @Environment(PlayerModel.self) private var player
    @Environment(BookmarkStore.self) private var store

    var body: some View {
        let groups = player.episodes
            .map { EpisodeBookmarks(episode: $0, bookmarks: store.bookmarks(for: $0.id)) }
            .filter { !$0.bookmarks.isEmpty }
        Group {
            if groups.isEmpty {
                EmptyBookmarks()
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.episode.title) {
                            ForEach(group.bookmarks) { bookmark in
                                Button {
                                    player.jump(to: bookmark)
                                    showPlayer(group.episode)
                                } label: {
                                    BookmarkRow(bookmark: bookmark)
                                }
                                .accessibilityIdentifier("bookmarkRow")
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    store.remove(id: group.bookmarks[index].id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
    }
}

/// The empty state. Built from text styles rather than ContentUnavailableView,
/// whose title stops growing before the largest Dynamic Type sizes (flagged by
/// the accessibility audit in WristCueUITests).
private struct EmptyBookmarks: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "bookmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No bookmarks yet")
                    .font(.title2.bold())
                Text("Tap Bookmark this moment in the player, or the bookmark button on your Apple Watch.")
                    .font(.body)
            }
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct EpisodeBookmarks: Identifiable {
    let episode: Episode
    let bookmarks: [Bookmark]
    var id: Episode.ID { episode.id }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark

    var body: some View {
        HStack {
            Text(TimeFormat.clock(bookmark.position))
                .font(.body.monospacedDigit())
            Spacer()
            Label(
                bookmark.source == .watch ? "Watch" : "iPhone",
                systemImage: bookmark.source == .watch ? "applewatch" : "iphone"
            )
            .font(.footnote)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bookmark at \(TimeFormat.spoken(bookmark.position)), saved on \(bookmark.source == .watch ? "Apple Watch" : "iPhone")")
        .accessibilityHint("Plays from this moment")
    }
}
