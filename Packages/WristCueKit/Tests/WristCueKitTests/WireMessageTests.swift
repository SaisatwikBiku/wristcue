import XCTest
@testable import WristCueKit

final class WireMessageTests: XCTestCase {
    private let codec = MessageCodec()

    private let samples: [WireMessage] = [
        WireMessage(payload: .state(Fixture.state(isPlaying: true)), sentAt: Fixture.t0),
        WireMessage(payload: .command(Fixture.command(.play)), sentAt: Fixture.t0),
        WireMessage(payload: .command(Fixture.command(.pause)), sentAt: Fixture.t0),
        WireMessage(payload: .command(Fixture.command(.skip(seconds: -15))), sentAt: Fixture.t0),
        WireMessage(payload: .command(Fixture.command(.seek(to: 61.5))), sentAt: Fixture.t0),
        WireMessage(payload: .command(Fixture.command(.setVolume(level: 0.25))), sentAt: Fixture.t0),
        WireMessage(payload: .command(Fixture.command(.addBookmark(bookmark: Fixture.bookmark()))), sentAt: Fixture.t0),
        WireMessage(
            payload: .bookmarks(BookmarkList(episodeID: "glance", bookmarks: [Fixture.bookmark(id: 1), Fixture.bookmark(id: 2)])),
            sentAt: Fixture.t0
        ),
    ]

    func testEveryPayloadRoundTripsThroughJSON() throws {
        for message in samples {
            let decoded = try codec.decode(codec.encode(message))
            XCTAssertEqual(decoded, message)
        }
    }

    func testEveryPayloadRoundTripsThroughWatchConnectivityDictionary() throws {
        for message in samples {
            let dictionary = try codec.dictionary(for: message)
            XCTAssertEqual(Array(dictionary.keys), [MessageCodec.dictionaryKey])
            XCTAssertEqual(try codec.message(from: dictionary), message)
        }
    }

    func testEncodingIsDeterministic() throws {
        let message = samples[0]
        XCTAssertEqual(try codec.encode(message), try codec.encode(message))
    }

    func testWireShapeHasVersionKindAndBody() throws {
        let data = try codec.encode(samples[0])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["kind"] as? String, "state")
        XCTAssertNotNil(json["body"] as? [String: Any])
    }

    func testKindMatchesPayload() {
        XCTAssertEqual(samples.map(\.kind), [.state, .command, .command, .command, .command, .command, .command, .bookmarks])
    }

    // MARK: Versioning

    func testRejectsNewerVersionBeforeReadingBody() {
        // The body is deliberately the wrong shape. The version check must fire first.
        let data = Data(#"{"version":2,"kind":"state","sentAt":0,"body":{"somethingNew":true}}"#.utf8)
        XCTAssertThrowsError(try codec.decode(data)) { error in
            XCTAssertEqual(error as? WireError, .unsupportedVersion(2))
        }
    }

    func testRejectsVersionBelowMinimum() {
        let data = Data(#"{"version":0,"kind":"state","sentAt":0,"body":{}}"#.utf8)
        XCTAssertThrowsError(try codec.decode(data)) { error in
            XCTAssertEqual(error as? WireError, .unsupportedVersion(0))
        }
    }

    func testRejectsUnknownKind() {
        let data = Data(#"{"version":1,"kind":"lyrics","sentAt":0,"body":{}}"#.utf8)
        XCTAssertThrowsError(try codec.decode(data)) { error in
            XCTAssertEqual(error as? WireError, .unknownKind("lyrics"))
        }
    }

    func testIgnoresUnknownFieldsFromSameVersion() throws {
        // Adding an optional field must not need a version bump.
        let original = samples[0]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: codec.encode(original)) as? [String: Any])
        json["addedInAFutureBuild"] = "ignored"
        var body = try XCTUnwrap(json["body"] as? [String: Any])
        body["chapterTitle"] = "Also ignored"
        json["body"] = body
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try codec.decode(data), original)
    }

    func testMissingVersionIsAnError() {
        let data = Data(#"{"kind":"state","sentAt":0,"body":{}}"#.utf8)
        XCTAssertThrowsError(try codec.decode(data))
    }

    func testGarbageIsAnError() {
        XCTAssertThrowsError(try codec.decode(Data("not json".utf8)))
    }

    func testDictionaryWithoutPayloadKeyIsAnError() {
        XCTAssertThrowsError(try codec.message(from: ["other": Data()])) { error in
            XCTAssertEqual(error as? WireError, .missingPayload)
        }
        XCTAssertThrowsError(try codec.message(from: [MessageCodec.dictionaryKey: "a string, not Data"])) { error in
            XCTAssertEqual(error as? WireError, .missingPayload)
        }
    }
}
