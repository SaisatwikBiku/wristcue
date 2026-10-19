import SwiftUI
import WristCueKit

/// The largest target on the screen: saves the moment heard now, with or without
/// the iPhone in reach.
struct BookmarkButton: View {
    @Environment(WatchSync.self) private var sync
    /// Set after a tap so the label confirms the save, then cleared.
    @State private var confirmation: String?

    var body: some View {
        Button {
            let reachable = sync.isReachable
            guard sync.addBookmark() != nil else { return }
            if reachable {
                Haptics.bookmarked()
            }
            confirmation = reachable ? "Saved" : "Saved, will sync"
        } label: {
            Label(confirmation ?? "Bookmark", systemImage: confirmation == nil ? "bookmark.fill" : "checkmark")
                .frame(maxWidth: .infinity)
        }
        .tint(.orange)
        .disabled(sync.displayState.episodeID == nil)
        .accessibilityLabel("Bookmark this moment")
        .accessibilityValue(confirmation ?? "")
        .task(id: confirmation) {
            guard confirmation != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            confirmation = nil
        }
    }
}
