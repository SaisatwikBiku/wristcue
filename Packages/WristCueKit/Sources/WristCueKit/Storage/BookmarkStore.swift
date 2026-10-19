import Foundation
import Observation

/// The iPhone's bookmarks, the single source of truth for every device.
///
/// Bookmarks are added by ID, so a bookmark that arrives twice (an interactive send
/// whose reply was lost, then the queued copy) is stored once.
@MainActor
@Observable
public final class BookmarkStore {
    public private(set) var bookmarks: [Bookmark]
    /// How many saves failed. The in-memory list stays correct either way.
    public private(set) var saveFailures = 0
    /// Called after every change. The app uses it to republish the list to the Watch.
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private let storage: JSONFileStore<[Bookmark]>?

    /// With `storage`, bookmarks persist across launches. Without it (tests,
    /// previews) they live in memory only.
    public init(storage: JSONFileStore<[Bookmark]>? = nil) {
        self.storage = storage
        bookmarks = (try? storage?.load()) ?? []
    }

    /// Adds a bookmark unless one with the same ID exists. Returns whether it was added.
    @discardableResult
    public func add(_ bookmark: Bookmark) -> Bool {
        guard !bookmarks.contains(where: { $0.id == bookmark.id }) else { return false }
        bookmarks.append(bookmark)
        didChange()
        return true
    }

    public func remove(id: Bookmark.ID) {
        let before = bookmarks.count
        bookmarks.removeAll { $0.id == id }
        if bookmarks.count != before {
            didChange()
        }
    }

    /// One episode's bookmarks in playback order.
    public func bookmarks(for episodeID: Episode.ID) -> [Bookmark] {
        bookmarks
            .filter { $0.episodeID == episodeID }
            .sorted { $0.position < $1.position }
    }

    private func didChange() {
        do {
            try storage?.save(bookmarks)
        } catch {
            saveFailures += 1
        }
        onChange?()
    }
}
