import XCTest
@testable import WristCueKit

/// The exact strings depend on the locale, so these tests check behavior that
/// holds in every locale rather than literal output.
final class TimeFormatTests: XCTestCase {
    func testBadInputIsTreatedAsZero() {
        XCTAssertEqual(TimeFormat.sanitized(.nan), 0)
        XCTAssertEqual(TimeFormat.sanitized(.infinity), 0)
        XCTAssertEqual(TimeFormat.sanitized(-4), 0)
        XCTAssertEqual(TimeFormat.sanitized(65), 65)
    }

    func testBadInputFormatsLikeZero() {
        XCTAssertEqual(TimeFormat.clock(.nan), TimeFormat.clock(0))
        XCTAssertEqual(TimeFormat.spoken(-1), TimeFormat.spoken(0))
    }

    func testDifferentTimesFormatDifferently() {
        XCTAssertNotEqual(TimeFormat.clock(5), TimeFormat.clock(65))
        XCTAssertNotEqual(TimeFormat.spoken(5), TimeFormat.spoken(65))
    }
}
