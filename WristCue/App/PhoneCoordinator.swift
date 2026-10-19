import Foundation
import Observation
import WristCueKit

/// Wires the iPhone's pieces together: the player, the bookmark store and sync.
///
/// The player and the store don't know about each other or about the Watch. This
/// is the one place that decides what a Watch command does and what gets
/// published back.
@MainActor
final class PhoneCoordinator {
    let player: PlayerModel
    let bookmarks: BookmarkStore
    private let sync: PhoneSync
    /// The bookmark list the Watch last received, so an unchanged list isn't sent again.
    private var publishedBookmarks: BookmarkList?

    init(transport: any ConnectivityTransport = WCSessionTransport()) {
        player = PlayerModel()
        bookmarks = BookmarkStore(storage: JSONFileStore(
            url: .applicationSupportDirectory.appending(path: "bookmarks.json")
        ))
        sync = PhoneSync(transport: transport)

        // Commands from the Watch take the same path as the app's own buttons.
        // A bookmark is stored first, then run through the player so the next
        // state carries its command ID and the Watch sees it acknowledged.
        sync.onCommand = { [weak self] command in
            guard let self else { return }
            if case .addBookmark(let bookmark) = command.action {
                bookmarks.add(bookmark)
            }
            player.perform(command)
        }
        // PlayerModel only reports real changes, so this is not a per-second stream.
        player.onStateChange = { [weak self] state in
            guard let self else { return }
            sync.publish(state)
            publishBookmarksIfChanged()
        }
        bookmarks.onChange = { [weak self] in
            self?.publishBookmarksIfChanged()
        }

        sync.publish(player.state)
        publishBookmarksIfChanged()
    }

    /// Sends the current episode's bookmarks when they differ from what the Watch
    /// already has: after an add or delete, or when the episode changes.
    private func publishBookmarksIfChanged() {
        let episodeID = player.currentEpisode?.id ?? ""
        let list = BookmarkList(episodeID: episodeID, bookmarks: bookmarks.bookmarks(for: episodeID))
        guard list != publishedBookmarks else { return }
        publishedBookmarks = list
        sync.publishBookmarks(list)
    }
}
