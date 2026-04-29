//
//  MeetingLinkDetectorTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class MeetingLinkDetectorTests: XCTestCase {
    private func outlookSafeLink(for url: String) -> String {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        return "https://nam11.safelinks.protection.outlook.com/?url=\(encodedURL ?? url)"
    }

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

    func testDetectsCustomRegexLinkFromNotes() {
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: "Join: https://example.test/meeting/abc",
            calendarEmail: nil,
            currentUserEmail: nil,
            customRegexes: [#"https://example\.test/meeting/[^\s]+"#]
        )
        XCTAssertEqual(link?.service, .other)
        XCTAssertEqual(link?.url.absoluteString, "https://example.test/meeting/abc")
    }

    func testCustomRegexesContinueAfterInvalidPattern() {
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: "Join: https://example.test/meeting/abc",
            calendarEmail: nil,
            currentUserEmail: nil,
            customRegexes: [
                "[",
                #"https://example\.test/meeting/[^\s]+"#
            ]
        )

        XCTAssertEqual(link?.service, .other)
        XCTAssertEqual(link?.url.absoluteString, "https://example.test/meeting/abc")
    }

    func testDetectsMeetingLinkInsideOutlookSafeLink() {
        let safeLink = outlookSafeLink(for: "https://meet.google.com/abc-defg-hij")
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: "Join: \(safeLink)",
            calendarEmail: nil,
            currentUserEmail: nil
        )

        XCTAssertEqual(link?.service, .meet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
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
        // HTML tag. HTML stripping only triggers entity-decoding when
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

    func testReturnsNilWhenKnownMeetingHostHasNoScheme() {
        let link = MeetingLinkDetector.detect(
            location: "meet.google.com/abc-defg-hij",
            eventURL: nil,
            notes: nil,
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

    func testCleanupOutlookSafeLinksDecodesMultipleLinks() {
        let meetURL = "https://meet.google.com/abc-defg-hij"
        let zoomURL = "https://us02web.zoom.us/j/12345"
        let cleaned = cleanupOutlookSafeLinks(
            rawText: "\(outlookSafeLink(for: meetURL)) \(outlookSafeLink(for: zoomURL))"
        )

        XCTAssertEqual(cleaned, "\(meetURL) \(zoomURL)")
    }

    func testCleanupOutlookSafeLinksLeavesPlainTextUnchanged() {
        let text = "Join https://meet.google.com/abc-defg-hij"

        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: text), text)
    }

    func testGetMatchReturnsFirstMatch() throws {
        let regex = try NSRegularExpression(pattern: #"https://example\.test/[a-z]+"#)
        let match = getMatch(
            text: "Join https://example.test/first then https://example.test/second",
            regex: regex
        )

        XCTAssertEqual(match, "https://example.test/first")
    }

    func testGetMatchReturnsNilWhenPatternDoesNotMatch() throws {
        let regex = try NSRegularExpression(pattern: #"https://example\.test/[a-z]+"#)

        XCTAssertNil(getMatch(text: "No links here", regex: regex))
    }

    func testHTMLTagsStrippedReturnsPlainTextUnchanged() {
        let text = "Join https://meet.google.com/abc-defg-hij"

        XCTAssertEqual(htmlTagsStrippedForMeetingLinks(text), text)
    }

    func testHTMLTagsStrippedDecodesVisibleHTMLText() {
        let stripped = htmlTagsStrippedForMeetingLinks(
            "<p>&#x68;&#x74;&#x74;&#x70;&#x73;://meet.google.com/abc-defg-hij</p>"
        )

        XCTAssertTrue(stripped.contains("https://meet.google.com/abc-defg-hij"))
        XCTAssertFalse(stripped.contains("<p>"))
    }
}
