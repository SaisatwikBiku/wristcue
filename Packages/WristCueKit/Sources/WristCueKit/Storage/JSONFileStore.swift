import Foundation

/// Saves one Codable value as a JSON file and reads it back.
///
/// Small on purpose: the Watch's offline queue and the iPhone's bookmarks are a few
/// kilobytes at most, so a whole-file rewrite is simpler than a database and easy
/// to inspect. Writes are atomic (write to a temporary file, then rename), so a
/// crash mid-write leaves the previous file intact.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The stored value, or nil when nothing has been saved yet. Throws when the
    /// file exists but can't be decoded.
    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
