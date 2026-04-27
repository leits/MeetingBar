//
//  MeetingLinkDetectorTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class MeetingLinkDetectorTests: BaseTestCase {
    func testDetectsMeetLinkFromLocation() {
        let link = MeetingLinkDetector.detect(
            location: "https://meet.google.com/abc-defg-hij",
            eventURL: nil,
            notes: nil,
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .meet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testDetectsZoomLinkFromEventURL() {
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: URL(string: "https://us02web.zoom.us/j/12345"),
            notes: nil,
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .zoom)
    }

    func testDetectsTeamsLinkFromNotes() {
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: "Join: https://teams.microsoft.com/l/meetup-join/abc",
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .teams)
    }

    func testDetectsLinkInsideHTMLAttributeWithoutStripping() {
        // The raw-notes pass already matches because the link regex has no
        // word boundaries, so `href="..."` markup around the URL does not
        // prevent a match. Guards that change in future regex tightening.
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: "<p>Join us</p><a href=\"https://meet.google.com/abc-defg-hij\">Open</a>",
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .meet)
    }

    func testDetectsLinkOnlyAfterHTMLStripping() {
        // The URL prefix is encoded with hex entities AND wrapped in a real
        // HTML tag. `htmlTagsStripped()` only triggers entity-decoding when
        // it sees a tag (containsHTML check), so we need both. Raw pass has
        // no literal "https://" and returns nil; the stripped pass produces
        // "https://meet.google.com/abc-defg-hij" and matches.
        let raw = "<p>&#x68;&#x74;&#x74;&#x70;&#x73;://meet.google.com/abc-defg-hij</p>"

        XCTAssertNil(
            detectMeetingLink(raw),
            "raw pass should not find a link before HTML decoding"
        )

        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: raw,
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .meet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testLocationBeatsEventURL() {
        let link = MeetingLinkDetector.detect(
            location: "https://meet.google.com/abc-defg-hij",
            eventURL: URL(string: "https://us02web.zoom.us/j/12345"),
            notes: "https://teams.microsoft.com/l/meetup-join/abc",
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .meet)
    }

    func testEventURLBeatsNotes() {
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: URL(string: "https://us02web.zoom.us/j/12345"),
            notes: "https://teams.microsoft.com/l/meetup-join/abc",
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .zoom)
    }

    func testGoogleMeetAppendsAuthuserFromCalendarEmail() {
        let link = MeetingLinkDetector.detect(
            location: "https://meet.google.com/abc-defg-hij",
            eventURL: nil,
            notes: nil,
            calendarEmail: "user@example.com",
            currentUserEmail: nil
        )
        XCTAssertEqual(
            link?.url.absoluteString,
            "https://meet.google.com/abc-defg-hij?authuser=user@example.com"
        )
    }

    func testGoogleMeetFallsBackToCurrentUserEmail() {
        let link = MeetingLinkDetector.detect(
            location: "https://meet.google.com/abc-defg-hij",
            eventURL: nil,
            notes: nil,
            calendarEmail: nil,
            currentUserEmail: "me@example.com"
        )
        XCTAssertEqual(
            link?.url.absoluteString,
            "https://meet.google.com/abc-defg-hij?authuser=me@example.com"
        )
    }

    func testCalendarEmailWinsOverCurrentUserEmail() {
        let link = MeetingLinkDetector.detect(
            location: "https://meet.google.com/abc-defg-hij",
            eventURL: nil,
            notes: nil,
            calendarEmail: "owner@example.com",
            currentUserEmail: "me@example.com"
        )
        XCTAssertEqual(
            link?.url.absoluteString,
            "https://meet.google.com/abc-defg-hij?authuser=owner@example.com"
        )
    }

    func testZoomURLDoesNotGetAuthuser() {
        let link = MeetingLinkDetector.detect(
            location: "https://us02web.zoom.us/j/12345",
            eventURL: nil,
            notes: nil,
            calendarEmail: "user@example.com",
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.url.absoluteString, "https://us02web.zoom.us/j/12345")
    }

    func testReturnsNilWhenNoFieldContainsLink() {
        let link = MeetingLinkDetector.detect(
            location: "Conference Room 5",
            eventURL: nil,
            notes: "Standup meeting",
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertNil(link)
    }

    func testReturnsNilForEmptyEvent() {
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: nil,
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertNil(link)
    }
}
