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

    func testEventURLBeatsLocation() {
        // Phase 3 candidate-based detection: structured eventURL field beats
        // free-text location. Old "first match wins" preferred location;
        // candidate model treats EKEvent.url style structured URLs as more
        // canonical than location text.
        let link = MeetingLinkDetector.detect(
            location: "https://meet.google.com/abc-defg-hij",
            eventURL: URL(string: "https://us02web.zoom.us/j/12345"),
            notes: "https://teams.microsoft.com/l/meetup-join/abc",
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .zoom)
    }

    func testProviderConferenceURLBeatsAllOtherSources() {
        // The headline #847 fix: Google Meet conferenceData beats a stale
        // Zoom link pasted in notes.
        let link = MeetingLinkDetector.detect(
            conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            location: nil,
            eventURL: URL(string: "https://us02web.zoom.us/j/12345"),
            notes: "Old reminder: https://us02web.zoom.us/j/99999",
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .meet)
    }

    func testAllCandidatesReturnsRankedAlternates() {
        let candidates = MeetingLinkDetector.allCandidates(
            conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            location: "https://teams.microsoft.com/l/meetup-join/location-link",
            eventURL: URL(string: "https://us02web.zoom.us/j/12345?pwd=abcdef"),
            notes: "Old reminder: https://us02web.zoom.us/j/99999",
            calendarEmail: nil,
            currentUserEmail: nil
        )

        XCTAssertEqual(candidates.map(\.source), [
            .providerConferenceData,
            .eventURL,
            .location,
            .notes
        ])
        XCTAssertEqual(candidates.first?.service, .meet)
        XCTAssertEqual(candidates.dropFirst().map(\.service), [.zoom, .teams, .zoom])
    }

    func testAllCandidatesAppliesMeetAuthuserToAlternates() {
        let candidates = MeetingLinkDetector.allCandidates(
            conferenceURL: nil,
            location: "https://us02web.zoom.us/j/12345",
            eventURL: URL(string: "https://meet.google.com/event-url"),
            notes: "Backup: https://meet.google.com/notes-link",
            calendarEmail: "owner@example.com",
            currentUserEmail: nil
        )

        XCTAssertEqual(
            candidates.map(\.url.absoluteString),
            [
                "https://meet.google.com/event-url?authuser=owner@example.com",
                "https://us02web.zoom.us/j/12345",
                "https://meet.google.com/notes-link?authuser=owner@example.com"
            ]
        )
    }

    func testCustomRegexBeatsNothingButLosesToBuiltInSources() {
        // Custom regex is the lowest priority fallback. With a built-in
        // service URL in any structured source, the custom regex must lose.
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            notes: "Use this internal room: https://internal.corp/room/42",
            calendarEmail: nil,
            currentUserEmail: nil,
            customRegexes: [#"https://internal\.corp/room/\d+"#]
        )
        XCTAssertEqual(link?.service, .meet,
                       "eventURL conferencing service must beat a custom regex match in notes")
    }

    func testAllCandidatesExposesCustomRegexCandidate() {
        let candidates = MeetingLinkDetector.allCandidates(
            location: nil,
            eventURL: nil,
            notes: "Use internal room: https://internal.corp/room/42",
            calendarEmail: nil,
            currentUserEmail: nil,
            customRegexes: [#"https://internal\.corp/room/\d+"#]
        )

        XCTAssertEqual(candidates.map(\.source), [.customRegex])
        XCTAssertEqual(candidates.first?.url.absoluteString, "https://internal.corp/room/42")
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

    func testLongerURLWinsWithinSameNotesSource() {
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: """
            Short form: https://us02web.zoom.us/j/12345
            Full form: https://us02web.zoom.us/j/12345?pwd=abcdef
            """,
            calendarEmail: nil,
            currentUserEmail: nil
        )

        XCTAssertEqual(link?.service, .zoom)
        XCTAssertEqual(link?.url.absoluteString, "https://us02web.zoom.us/j/12345?pwd=abcdef")
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

    func testGoogleMeetConferenceURLPreservesExistingQueryWhenAddingAuthuser() {
        let link = MeetingLinkDetector.detect(
            conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij?pli=1"),
            location: nil,
            eventURL: nil,
            notes: nil,
            calendarEmail: "user@example.com",
            currentUserEmail: nil
        )

        let components = link.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false) }
        XCTAssertEqual(link?.service, .meet)
        XCTAssertEqual(components?.queryItems?.first { $0.name == "pli" }?.value, "1")
        XCTAssertEqual(components?.queryItems?.first { $0.name == "authuser" }?.value, "user@example.com")
    }

    func testGoogleMeetConferenceURLReplacesExistingAuthuser() {
        let link = MeetingLinkDetector.detect(
            conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij?authuser=old@example.com"),
            location: nil,
            eventURL: nil,
            notes: nil,
            calendarEmail: "owner@example.com",
            currentUserEmail: nil
        )

        let authuserItems = link.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false) }?
            .queryItems?
            .filter { $0.name == "authuser" }
        XCTAssertEqual(authuserItems?.map(\.value), ["owner@example.com"])
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
