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

    func testDetectsLinkFromHTMLStrippedNotes() {
        // Notes contain only an HTML-encoded link with surrounding markup.
        // The first pass on raw notes should pick it up because the regex does
        // not require word boundaries; this test guards that fallback path
        // exists for future markup variations.
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: "<p>Join us</p><a href=\"https://meet.google.com/abc-defg-hij\">Open</a>",
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .meet)
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
