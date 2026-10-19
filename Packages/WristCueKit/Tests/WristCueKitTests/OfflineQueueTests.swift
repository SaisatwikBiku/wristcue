import XCTest
@testable import WristCueKit

final class OfflineQueueTests: XCTestCase {
    func testKeepsFirstInFirstOutOrder() {
        var queue = OfflineQueue()
        queue.enqueue(Fixture.command(.skip(seconds: 30), id: 1))
        queue.enqueue(Fixture.command(.addBookmark(bookmark: Fixture.bookmark()), id: 2))
        queue.enqueue(Fixture.command(.skip(seconds: -15), id: 3))
        XCTAssertEqual(queue.pending.map(\.id), [1, 2, 3].map(Fixture.uuid))
    }

    func testDropsDuplicateOfPendingCommand() {
        var queue = OfflineQueue()
        let command = Fixture.command(.skip(seconds: 30))
        XCTAssertEqual(queue.enqueue(command), .queued)
        XCTAssertEqual(queue.enqueue(command), .duplicate)
        XCTAssertEqual(queue.pending.count, 1)
    }

    func testDropsDuplicateOfDeliveredCommand() {
        var queue = OfflineQueue()
        let command = Fixture.command(.addBookmark(bookmark: Fixture.bookmark()))
        queue.enqueue(command)
        queue.markDelivered([command.id])
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.enqueue(command), .duplicate)
        XCTAssertTrue(queue.isEmpty)
    }

    func testMarkDeliveredRemovesOnlyThoseIDs() {
        var queue = OfflineQueue()
        queue.enqueue(Fixture.command(.skip(seconds: 30), id: 1))
        queue.enqueue(Fixture.command(.skip(seconds: 30), id: 2))
        queue.markDelivered([Fixture.uuid(1)])
        XCTAssertEqual(queue.pending.map(\.id), [Fixture.uuid(2)])
    }

    func testVolumeChangesCollapseToNewest() {
        var queue = OfflineQueue()
        queue.enqueue(Fixture.command(.setVolume(level: 0.2), id: 1))
        queue.enqueue(Fixture.command(.skip(seconds: 30), id: 2))
        XCTAssertEqual(queue.enqueue(Fixture.command(.setVolume(level: 0.9), id: 3)), .replaced(Fixture.uuid(1)))
        XCTAssertEqual(queue.pending.map(\.id), [2, 3].map(Fixture.uuid))
    }

    func testPlayAndPauseCollapseToNewest() {
        var queue = OfflineQueue()
        queue.enqueue(Fixture.command(.play, id: 1))
        queue.enqueue(Fixture.command(.pause, id: 2))
        queue.enqueue(Fixture.command(.play, id: 3))
        XCTAssertEqual(queue.pending.map(\.id), [Fixture.uuid(3)])
    }

    func testSeeksCollapseToNewest() {
        var queue = OfflineQueue()
        queue.enqueue(Fixture.command(.seek(to: 10), id: 1))
        queue.enqueue(Fixture.command(.seek(to: 50), id: 2))
        XCTAssertEqual(queue.pending.map(\.action), [.seek(to: 50)])
    }

    func testReplacedCommandCountsAsSettled() {
        var queue = OfflineQueue()
        let first = Fixture.command(.setVolume(level: 0.2), id: 1)
        queue.enqueue(first)
        queue.enqueue(Fixture.command(.setVolume(level: 0.9), id: 2))
        XCTAssertEqual(queue.enqueue(first), .duplicate)
    }

    func testSkipsAndBookmarksNeverCollapse() {
        var queue = OfflineQueue()
        queue.enqueue(Fixture.command(.skip(seconds: 30), id: 1))
        queue.enqueue(Fixture.command(.skip(seconds: 30), id: 2))
        queue.enqueue(Fixture.command(.addBookmark(bookmark: Fixture.bookmark(id: 10)), id: 3))
        queue.enqueue(Fixture.command(.addBookmark(bookmark: Fixture.bookmark(id: 11)), id: 4))
        XCTAssertEqual(queue.pending.count, 4)
    }

    func testExpiresStalePlaybackCommandsButKeepsBookmarks() {
        var queue = OfflineQueue(maxPlaybackCommandAge: 30)
        queue.enqueue(Fixture.command(.skip(seconds: 30), id: 1, secondsAfterT0: 0))
        queue.enqueue(Fixture.command(.addBookmark(bookmark: Fixture.bookmark()), id: 2, secondsAfterT0: 0))
        queue.enqueue(Fixture.command(.pause, id: 3, secondsAfterT0: 50))

        let expired = queue.removeExpired(now: Fixture.t0.addingTimeInterval(60))

        XCTAssertEqual(expired.map(\.id), [Fixture.uuid(1)])
        XCTAssertEqual(queue.pending.map(\.id), [2, 3].map(Fixture.uuid))
        XCTAssertEqual(queue.enqueue(Fixture.command(.skip(seconds: 30), id: 1)), .duplicate)
    }

    func testSurvivesPersistence() throws {
        var queue = OfflineQueue()
        queue.enqueue(Fixture.command(.addBookmark(bookmark: Fixture.bookmark()), id: 1))
        queue.enqueue(Fixture.command(.skip(seconds: 30), id: 2))
        queue.markDelivered([Fixture.uuid(2)])

        let restored = try JSONDecoder().decode(OfflineQueue.self, from: JSONEncoder().encode(queue))

        XCTAssertEqual(restored.pending, queue.pending)
        XCTAssertEqual(restored.maxPlaybackCommandAge, queue.maxPlaybackCommandAge)
        var copy = restored
        XCTAssertEqual(copy.enqueue(Fixture.command(.skip(seconds: 30), id: 2)), .duplicate)
    }

    // MARK: RecentIDs

    func testRecentIDsRejectsRepeats() {
        var ids = RecentIDs<Int>(capacity: 3)
        XCTAssertTrue(ids.insert(1))
        XCTAssertFalse(ids.insert(1))
        XCTAssertEqual(ids.count, 1)
    }

    func testRecentIDsForgetsOldestBeyondCapacity() {
        var ids = RecentIDs<Int>(capacity: 3)
        for id in 1...4 {
            ids.insert(id)
        }
        XCTAssertEqual(ids.count, 3)
        XCTAssertFalse(ids.contains(1))
        XCTAssertTrue(ids.contains(2))
        XCTAssertTrue(ids.contains(4))
    }
}
