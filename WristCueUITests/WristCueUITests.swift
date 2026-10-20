import XCTest

/// End-to-end checks of the iPhone app in the Simulator. The app is launched with
/// `-WristCueUITesting YES`, which gives it an empty in-memory bookmark list.
///
/// The Watch app has no UI tests. These cover the iPhone screens; the Watch
/// screens were checked by hand (README, milestone checks).
final class WristCueUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WristCueUITesting", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    func testListShowsEveryEpisode() {
        let app = launch()
        for id in ["glance", "crown", "remote", "codec"] {
            XCTAssertTrue(element("episode.\(id)", in: app).waitForExistence(timeout: 5), "Missing episode \(id)")
        }
    }

    @MainActor
    func testOpeningAnEpisodeShowsThePlayer() {
        let app = launch()
        element("episode.glance", in: app).tap()

        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5), "Playback should start when the player opens")
        XCTAssertTrue(app.buttons["Skip back 15 seconds"].exists)
        XCTAssertTrue(app.buttons["Skip forward 30 seconds"].exists)
    }

    @MainActor
    func testBookmarkFromPlayerIsListed() {
        let app = launch()
        element("episode.glance", in: app).tap()

        let bookmark = element("bookmarkButton", in: app)
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        element("bookmarksLink", in: app).tap()

        XCTAssertTrue(element("bookmarkRow", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testBookmarksStartEmpty() {
        let app = launch()
        element("bookmarksLink", in: app).tap()

        XCTAssertTrue(app.staticTexts["No bookmarks yet"].waitForExistence(timeout: 5))
    }

    /// Xcode's built-in accessibility audit: contrast, element descriptions, hit
    /// region sizes, Dynamic Type clipping and more.
    @MainActor
    func testEpisodeListPassesAccessibilityAudit() throws {
        let app = launch()
        XCTAssertTrue(element("episode.glance", in: app).waitForExistence(timeout: 5))
        try audit(app)
    }

    @MainActor
    func testBookmarksScreenPassesAccessibilityAudit() throws {
        let app = launch()
        element("bookmarksLink", in: app).tap()
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].waitForExistence(timeout: 5))
        try audit(app)
    }

    /// Runs the audit and prints each issue with the element it's about, as
    /// `WRISTCUE_AUDIT` lines. Every issue is still reported as a failure.
    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map {
                "type=\($0.elementType.rawValue) label='\($0.label)' id='\($0.identifier)' frame=\($0.frame)"
            } ?? "no element"
            print("WRISTCUE_AUDIT \(issue.compactDescription) | \(issue.detailedDescription) | \(element)")
            return false
        }
    }
}
