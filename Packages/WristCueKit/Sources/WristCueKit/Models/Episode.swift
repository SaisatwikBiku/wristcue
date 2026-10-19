import Foundation

/// One bundled audio episode.
///
/// The iPhone owns the audio file. The Watch only needs the metadata, so both apps
/// read the same catalog from the kit and the wire protocol only carries the ID.
public struct Episode: Codable, Hashable, Sendable, Identifiable {
    /// A short readable string instead of a UUID, so IDs are stable across launches
    /// and devices and easy to read in logs.
    public let id: String
    public let title: String
    public let summary: String
    /// File name inside the iPhone app bundle.
    public let audioFileName: String

    public init(id: String, title: String, summary: String, audioFileName: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.audioFileName = audioFileName
    }
}

extension Episode {
    /// The bundled library. The audio is synthetic, generated with the macOS `say`
    /// command from the text files in scripts/episodes/ (see scripts/make-audio.sh).
    public static let library: [Episode] = [
        Episode(
            id: "glance",
            title: "Designing for the Glance",
            summary: "Why a wrist interface has a few seconds to make its point.",
            audioFileName: "ep1-glance.m4a"
        ),
        Episode(
            id: "crown",
            title: "The Crown as a Volume Knob",
            summary: "Physical input, detents, and why a dial beats a slider on a small screen.",
            audioFileName: "ep2-crown.m4a"
        ),
        Episode(
            id: "remote",
            title: "Why Remotes Feel Slow",
            summary: "Where the milliseconds go between a tap on the wrist and sound from the phone.",
            audioFileName: "ep3-remote.m4a"
        ),
        Episode(
            id: "codec",
            title: "How a Voice Becomes AAC",
            summary: "Sampling, compression, and what a podcast file actually contains.",
            audioFileName: "ep4-codec.m4a"
        ),
    ]

    /// Looks up a bundled episode by ID.
    public static func withID(_ id: ID) -> Episode? {
        library.first { $0.id == id }
    }
}
