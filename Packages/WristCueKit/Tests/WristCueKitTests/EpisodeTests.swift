import XCTest
@testable import WristCueKit

final class EpisodeTests: XCTestCase {
    func testLibraryHasThreeOrFourEpisodes() {
        XCTAssertTrue((3...4).contains(Episode.library.count))
    }

    func testEpisodeIDsAndFilesAreUnique() {
        XCTAssertEqual(Set(Episode.library.map(\.id)).count, Episode.library.count)
        XCTAssertEqual(Set(Episode.library.map(\.audioFileName)).count, Episode.library.count)
    }

    func testAudioFilesAreAAC() {
        XCTAssertTrue(Episode.library.allSatisfy { $0.audioFileName.hasSuffix(".m4a") })
    }

    func testLookupByID() {
        XCTAssertEqual(Episode.withID("crown")?.title, "The Crown as a Volume Knob")
        XCTAssertNil(Episode.withID("missing"))
    }

    func testBookmarkDefaultsToFreshIDs() {
        let first = Bookmark(episodeID: "glance", position: 1, source: .phone)
        let second = Bookmark(episodeID: "glance", position: 1, source: .phone)
        XCTAssertNotEqual(first.id, second.id)
    }
}
