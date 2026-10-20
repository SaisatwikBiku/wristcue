import Foundation

/// Everything that crosses between the iPhone and the Watch.
///
/// On the wire it is JSON shaped like:
///
///     {"version": 1, "kind": "state", "sentAt": 782000000, "body": { ... }}
///
/// `version` is decoded before anything else. If a newer app sends a format this
/// build doesn't understand, decoding fails with `WireError.unsupportedVersion`
/// before it tries to read a body whose shape may have changed. The two apps can be
/// out of date with each other for real (the Watch app can update on its own), so
/// this check is a requirement, not decoration.
public struct WireMessage: Hashable, Sendable {
    /// Bump when a change would break older readers: a renamed or retyped field,
    /// or new required data. Adding an optional field doesn't need a bump, because
    /// JSONDecoder ignores keys it doesn't know.
    public static let currentVersion = 1
    public static let minimumSupportedVersion = 1

    public let version: Int
    /// Sender's clock time. Used for logging and staleness checks.
    public let sentAt: Date
    public let payload: Payload

    public init(payload: Payload, sentAt: Date = .now, version: Int = WireMessage.currentVersion) {
        self.version = version
        self.sentAt = sentAt
        self.payload = payload
    }

    public var kind: Kind { payload.kind }

    public enum Payload: Hashable, Sendable {
        case state(PlaybackState)
        case command(Command)
        case bookmarks(BookmarkList)
        /// Asks the other side for its newest value of one kind, answered in the
        /// reply to this live message. The Watch sends it when it connects.
        /// Adding a kind needs no version bump: an older build drops a message
        /// whose kind it doesn't know and keeps reading the others.
        case request(Kind)

        public var kind: Kind {
            switch self {
            case .state: return .state
            case .command: return .command
            case .bookmarks: return .bookmarks
            case .request: return .request
            }
        }
    }

    /// The `kind` string on the wire. Also used as the key for each latest-value
    /// slot in the application context, so state and bookmarks never overwrite
    /// each other.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case state
        case command
        case bookmarks
        case request
    }
}

public enum WireError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case unknownKind(String)
    /// The WatchConnectivity dictionary had no encoded message under the expected key.
    case missingPayload
}

// Codable is written by hand here (instead of synthesized) for two reasons: to check
// the version before reading the body, and to give the wire a flat, readable
// "kind" + "body" shape instead of Swift's default enum encoding.
extension WireMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, sentAt, kind, body
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard (Self.minimumSupportedVersion...Self.currentVersion).contains(version) else {
            throw WireError.unsupportedVersion(version)
        }
        let rawKind = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            throw WireError.unknownKind(rawKind)
        }
        switch kind {
        case .state:
            payload = try .state(container.decode(PlaybackState.self, forKey: .body))
        case .command:
            payload = try .command(container.decode(Command.self, forKey: .body))
        case .bookmarks:
            payload = try .bookmarks(container.decode(BookmarkList.self, forKey: .body))
        case .request:
            payload = try .request(container.decode(Kind.self, forKey: .body))
        }
        self.version = version
        sentAt = try container.decode(Date.self, forKey: .sentAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(sentAt, forKey: .sentAt)
        try container.encode(kind, forKey: .kind)
        switch payload {
        case .state(let state): try container.encode(state, forKey: .body)
        case .command(let command): try container.encode(command, forKey: .body)
        case .bookmarks(let list): try container.encode(list, forKey: .body)
        case .request(let kind): try container.encode(kind, forKey: .body)
        }
    }
}
