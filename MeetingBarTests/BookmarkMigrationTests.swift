//
//  BookmarkMigrationTests.swift
//  MeetingBarTests
//
//  Verifies that Bookmark decodes correctly from both the old encoding
//  (service: MeetingServices) and the new encoding (service: String).
//
//  Phase 3 PR 6: Bookmark.service changed from MeetingServices to String.
//  Old stored JSON used the MeetingServices rawValue as the encoded string,
//  which is identical to the new String encoding, so decoding is transparent.
//

import XCTest

@testable import MeetingBar

final class BookmarkMigrationTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - Backward-compat decoding

    func testDecodesBookmarkFromLegacyJSON_meet() throws {
        // Old format: service key holds MeetingServices rawValue string
        let json = Data(
            """
            {"name":"Daily","service":"Google Meet","url":"https://meet.google.com/abc"}
            """.utf8)
        let bookmark = try decoder.decode(Bookmark.self, from: json)
        XCTAssertEqual(bookmark.name, "Daily")
        XCTAssertEqual(bookmark.service, "Google Meet")
        XCTAssertEqual(bookmark.url.absoluteString, "https://meet.google.com/abc")
    }

    func testDecodesBookmarkFromLegacyJSON_zoom() throws {
        let json = Data(
            """
            {"name":"Standup","service":"Zoom","url":"https://zoom.us/j/123"}
            """.utf8)
        let bookmark = try decoder.decode(Bookmark.self, from: json)
        XCTAssertEqual(bookmark.service, "Zoom")
    }

    func testDecodesBookmarkFromLegacyJSON_teams() throws {
        let json = Data(
            """
            {"name":"Sprint","service":"Microsoft Teams","url":"https://teams.microsoft.com/l/meetup-join/1"}
            """.utf8)
        let bookmark = try decoder.decode(Bookmark.self, from: json)
        XCTAssertEqual(bookmark.service, "Microsoft Teams")
    }

    func testDecodesBookmarkFromLegacyJSON_unknownService() throws {
        // A future/unknown provider should decode as-is, not throw
        let json = Data(
            """
            {"name":"Custom","service":"My Custom Provider","url":"https://custom.example.com"}
            """.utf8)
        let bookmark = try decoder.decode(Bookmark.self, from: json)
        XCTAssertEqual(bookmark.service, "My Custom Provider")
    }

    // MARK: - Round-trip encoding

    func testRoundTripEncoding() throws {
        let original = Bookmark(
            name: "Weekly Sync",
            service: MeetingServices.zoom.rawValue,
            url: URL(string: "https://zoom.us/j/987654")!
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Bookmark.self, from: data)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.service, original.service)
        XCTAssertEqual(decoded.url, original.url)
    }

    func testEncodedJSONUsesServiceKey() throws {
        let bookmark = Bookmark(
            name: "Meet",
            service: "Google Meet",
            url: URL(string: "https://meet.google.com/xyz")!
        )
        let data = try encoder.encode(bookmark)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["service"] as? String, "Google Meet")
    }

    // MARK: - Service ID matches MeetingServices rawValue

    func testMeetingServicesRawValuesAreUsedAsServiceIDs() {
        // Critical: Bookmark.service stores the same string as MeetingServices.rawValue
        XCTAssertEqual(MeetingServices.meet.rawValue, "Google Meet")
        XCTAssertEqual(MeetingServices.zoom.rawValue, "Zoom")
        XCTAssertEqual(MeetingServices.teams.rawValue, "Microsoft Teams")
        XCTAssertEqual(MeetingServices.jitsi.rawValue, "Jitsi")
        XCTAssertEqual(MeetingServices.slack.rawValue, "Slack")
        XCTAssertEqual(MeetingServices.riverside.rawValue, "Riverside")
    }
}
