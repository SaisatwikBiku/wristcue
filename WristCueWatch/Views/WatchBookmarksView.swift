import SwiftUI
import WristCueKit

/// The current episode's bookmarks. Tap one to play from there on the iPhone.
/// Bookmarks the iPhone hasn't confirmed yet are marked as waiting.
struct WatchBookmarksView: View {
    @Environment(WatchSync.self) private var sync
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = sync.bookmarkItems
        Group {
            if items.isEmpty {
                ContentUnavailableView("No bookmarks", systemImage: "bookmark")
            } else {
                List(items) { item in
                    Button {
                        Haptics.play(for: .seek(to: item.bookmark.position))
                        sync.send(.seek(to: item.bookmark.position))
                        dismiss()
                    } label: {
                        HStack {
                            Text(TimeFormat.clock(item.bookmark.position))
                                .font(.body.monospacedDigit())
                            Spacer()
                            if item.isPending {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .accessibilityLabel("Bookmark at \(TimeFormat.spoken(item.bookmark.position))")
                    .accessibilityValue(item.isPending ? "Waiting for iPhone" : "")
                    .accessibilityHint("Plays from this moment")
                }
            }
        }
        .navigationTitle("Bookmarks")
    }
}
