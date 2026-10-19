import Foundation

/// Which device created something. Stored on bookmarks so the UI can show where a
/// moment was saved.
public enum DeviceRole: String, Codable, Sendable {
    case phone
    case watch
}

/// A saved moment: a position in one episode.
public struct Bookmark: Codable, Hashable, Sendable, Identifiable {
    /// Generated on the device that creates the bookmark. Because the ID exists before
    /// the bookmark is sent, the receiver can drop a copy that arrives twice.
    public let id: UUID
    public let episodeID: Episode.ID
    /// Seconds from the start of the episode.
    public let position: TimeInterval
    public let createdAt: Date
    public let source: DeviceRole

    public init(
        id: UUID = UUID(),
        episodeID: Episode.ID,
        position: TimeInterval,
        createdAt: Date = .now,
        source: DeviceRole
    ) {
        self.id = id
        self.episodeID = episodeID
        self.position = position
        self.createdAt = createdAt
        self.source = source
    }
}

/// The iPhone's bookmarks for one episode, sent to the Watch as a whole list.
/// Only the newest list matters, so it travels as application context.
public struct BookmarkList: Codable, Hashable, Sendable {
    public let episodeID: Episode.ID
    public let bookmarks: [Bookmark]

    public init(episodeID: Episode.ID, bookmarks: [Bookmark]) {
        self.episodeID = episodeID
        self.bookmarks = bookmarks
    }
}
