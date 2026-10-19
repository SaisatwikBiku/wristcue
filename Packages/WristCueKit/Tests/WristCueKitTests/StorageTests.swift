import XCTest
@testable import WristCueKit

private func temporaryURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appending(path: name)
}

final class JSONFileStoreTests: XCTestCase {
    func testMissingFileLoadsAsNil() throws {
        let store = JSONFileStore<[Int]>(url: temporaryURL("missing.json"))
        XCTAssertNil(try store.load())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = JSONFileStore<[Bookmark]>(url: temporaryURL("bookmarks.json"))
        let bookmarks = [Fixture.bookmark(id: 1), Fixture.bookmark(id: 2, position: 7)]

        try store.save(bookmarks)

        XCTAssertEqual(try store.load(), bookmarks)
    }

    func testCorruptFileThrows() throws {
        let url = temporaryURL("corrupt.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        XCTAssertThrowsError(try JSONFileStore<[Int]>(url: url).load())
    }
}

/// Values are copied into locals before XCTAssert, whose autoclosures aren't
/// main-actor isolated.
final class BookmarkStoreTests: XCTestCase {
    @MainActor
    func testAddingTheSameBookmarkTwiceStoresItOnce() {
        let store = BookmarkStore()
        let bookmark = Fixture.bookmark()

        let first = store.add(bookmark)
        let second = store.add(bookmark)

        let count = store.bookmarks.count
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testBookmarksForAnEpisodeAreInPlaybackOrder() {
        let store = BookmarkStore()
        store.add(Fixture.bookmark(id: 1, position: 50))
        store.add(Fixture.bookmark(id: 2, position: 10))
        store.add(Bookmark(id: Fixture.uuid(3), episodeID: "crown", position: 30, createdAt: Fixture.t0, source: .phone))

        let positions = store.bookmarks(for: "glance").map(\.position)
        XCTAssertEqual(positions, [10, 50])
    }

    @MainActor
    func testRemoveDeletesOnlyThatBookmark() {
        let store = BookmarkStore()
        store.add(Fixture.bookmark(id: 1))
        store.add(Fixture.bookmark(id: 2))

        store.remove(id: Fixture.uuid(1))
        store.remove(id: Fixture.uuid(99))

        let ids = store.bookmarks.map(\.id)
        XCTAssertEqual(ids, [Fixture.uuid(2)])
    }

    @MainActor
    func testChangesAreReportedAndPersisted() throws {
        let storage = JSONFileStore<[Bookmark]>(url: temporaryURL("bookmarks.json"))
        let store = BookmarkStore(storage: storage)
        let counter = ChangeCounter()
        store.onChange = { counter.count += 1 }

        store.add(Fixture.bookmark(id: 1))
        store.add(Fixture.bookmark(id: 1))
        store.remove(id: Fixture.uuid(1))
        store.add(Fixture.bookmark(id: 2))

        let changes = counter.count
        let reloaded = BookmarkStore(storage: storage).bookmarks.map(\.id)
        let failures = store.saveFailures
        XCTAssertEqual(changes, 3, "A duplicate add is not a change")
        XCTAssertEqual(reloaded, [Fixture.uuid(2)])
        XCTAssertEqual(failures, 0)
    }

    @MainActor
    func testFailedSaveIsCountedAndListStaysInMemory() throws {
        // A file where the store's folder should be makes every save fail.
        let blocker = temporaryURL("blocker")
        try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: blocker)
        let store = BookmarkStore(storage: JSONFileStore(url: blocker.appending(path: "bookmarks.json")))

        store.add(Fixture.bookmark())

        let failures = store.saveFailures
        let count = store.bookmarks.count
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(count, 1)
    }
}

@MainActor
private final class ChangeCounter {
    var count = 0
}
