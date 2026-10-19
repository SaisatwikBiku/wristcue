import Foundation

/// Turns `WireMessage` values into bytes and back, and wraps them in the
/// dictionaries WatchConnectivity expects.
///
/// WatchConnectivity only accepts property-list dictionaries ([String: Any] holding
/// strings, numbers, dates, data and so on). Rather than hand-mapping every field
/// into that dictionary, the whole message is JSON-encoded into one `Data` value
/// under one key. Codable then does all the type checking on both ends.
public struct MessageCodec: Sendable {
    /// The single key used in every WatchConnectivity dictionary.
    public static let dictionaryKey = "m"

    public init() {}

    public func encode(_ message: WireMessage) throws -> Data {
        // A fresh encoder per call keeps this type trivially Sendable. Creating a
        // JSONEncoder is cheap next to the encoding work itself.
        let encoder = JSONEncoder()
        // Sorted keys make the output byte-for-byte deterministic, so payload size
        // measurements are repeatable.
        encoder.outputFormatting = .sortedKeys
        // Encodes Date as its raw Double, which round-trips exactly.
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(message)
    }

    public func decode(_ data: Data) throws -> WireMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(WireMessage.self, from: data)
    }

    public func dictionary(for message: WireMessage) throws -> [String: Any] {
        [Self.dictionaryKey: try encode(message)]
    }

    public func message(from dictionary: [String: Any]) throws -> WireMessage {
        guard let data = dictionary[Self.dictionaryKey] as? Data else {
            throw WireError.missingPayload
        }
        return try decode(data)
    }
}
