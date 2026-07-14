//
//  MeetingLinkDetectorTests.swift
//  MeetingBarLogicTests
//

import Darwin.Mach
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

    func testDetectsProtonMeetLinkAndPreservesFragment() {
        let url = "https://meet.proton.me/join/id-FRMQ717ZMW#pwd-GoslDQl8D7mu"
        let link = detectMeetingLink(url)

        XCTAssertEqual(link?.service, .protonMeet)
        XCTAssertEqual(link?.url.absoluteString, url)
    }

    func testDetectsProtonMeetLinkAndPreservesQuery() {
        let url = "https://meet.proton.me/join/id-FRMQ717ZMW?ref=calendar"
        let link = detectMeetingLink(url)

        XCTAssertEqual(link?.service, .protonMeet)
        XCTAssertEqual(link?.url.absoluteString, url)
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

    func testDetectsExistingWorkplaceGroupCallLink() {
        let url = "https://workplace.com/groupcall/123456?token=abc"
        let link = detectMeetingLink(url)

        XCTAssertEqual(link?.service, .facebook_workspace)
        XCTAssertEqual(link?.url.absoluteString, url)
    }

    func testDetectsLegacyTeamsMeetupJoinURLWithAdditionalQueryParameters() {
        let url = "https://teams.microsoft.com/l/meetup-join/abc?context=xyz&anon=true"
        let link = detectMeetingLink(url)

        XCTAssertEqual(link?.service, .teams)
        XCTAssertEqual(link?.url.absoluteString, url)
    }

    func testDetectsTeamsShortURL() {
        let url = "https://teams.microsoft.com/meet/1234567890123?p=Aa1Bb2Cc3Dd4Ee5"
        let link = detectMeetingLink(url)

        XCTAssertEqual(link?.service, .teams)
        XCTAssertEqual(link?.url.absoluteString, url)
    }

    func testDetectsTeamsShortURLWithAdditionalQueryParameters() {
        let url = "https://teams.microsoft.com/meet/1234567890123?p=Aa1Bb2Cc3Dd4Ee5&anon=true"
        let link = detectMeetingLink(url)

        XCTAssertEqual(link?.service, .teams)
        XCTAssertEqual(link?.url.absoluteString, url)
    }

    func testDetectsSupportedTeamsGovernmentHosts() {
        let urls = [
            "https://teams.microsoft.us/meet/1234567890123?p=Aa1Bb2Cc3Dd4Ee5",
            "https://gov.teams.microsoft.com/meet/1234567890123?p=Aa1Bb2Cc3Dd4Ee5",
            "https://gov.teams.microsoft.us/l/meetup-join/abc?context=xyz"
        ]

        for url in urls {
            let link = detectMeetingLink(url)

            XCTAssertEqual(link?.service, .teams, url)
            XCTAssertEqual(link?.url.absoluteString, url)
        }
    }

    func testDoesNotMatchUnrelatedTeamsPages() {
        let urls = [
            "https://teams.microsoft.com/",
            "https://teams.microsoft.com/l/meeting/new",
            "https://teams.microsoft.com/meet/1234567890123",
            "https://teams.microsoft.com/meet/channel?p=Aa1Bb2Cc3Dd4Ee5"
        ]

        for url in urls {
            XCTAssertNil(detectMeetingLink(url), url)
        }
    }

    func testDetectsZhumuMeetingLinkVariants() {
        // Real Zhumu/WeMeeting join formats: a `/j/` link with an optional
        // `?pwd=` passcode, and the web-client `/wc/join/` link with a `?wpk=`
        // key. The original pattern used `[0-9]+?pwd=` (a lazy quantifier that
        // ate the `?`), so it never matched a real link.
        let urls = [
            "https://welink.zhumu.com/j/154051242?pwd=abc123",
            "https://welink.zhumu.com/j/150525986",
            "https://welink.zhumu.com/wc/join/150525986?wpk=wcpk5b53"
        ]

        for url in urls {
            let link = detectMeetingLink(url)

            XCTAssertEqual(link?.service, .zhumu, url)
            XCTAssertEqual(link?.url.absoluteString, url, url)
        }
    }

    func testDoesNotMatchNonMeetingZhumuPages() {
        let urls = [
            "https://welink.zhumu.com/download",
            "https://welink.zhumu.com/j/",
            // The web-client form is only a real meeting link with its `?wpk=`
            // key; a bare `/wc/join/<id>` is not.
            "https://welink.zhumu.com/wc/join/150525986"
        ]

        for url in urls {
            XCTAssertNil(detectMeetingLink(url), url)
        }
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

    func testGoogleMeetAppendsAuthuserFromCurrentUserEmail() {
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

    func testGoogleMeetPrefersCurrentUserEmailOverCalendarEmail() {
        // With multiple calendars connected to one account, the current-user
        // attendee identity resolves the correct Google account better than
        // the calendar's own email.
        let link = MeetingLinkDetector.detect(
            location: "https://meet.google.com/abc-defg-hij",
            eventURL: nil,
            notes: nil,
            calendarEmail: "calendar@example.com",
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

    func testHTMLStripReconnectsAmpEncodedURL() {
        // The whole point of stripping notes for link detection: HTML-encoded
        // query separators (&amp;) must decode so the URL regex sees one link.
        let stripped = htmlTagsStrippedForMeetingLinks(
            "<p>Join https://us02web.zoom.us/j/123?pwd=abc&amp;uname=sam</p>"
        )

        XCTAssertTrue(stripped.contains("https://us02web.zoom.us/j/123?pwd=abc&uname=sam"))
        XCTAssertFalse(stripped.contains("&amp;"))
    }

    func testHTMLStripDecodesNamedAndNumericEntities() {
        let stripped = htmlTagsStrippedForMeetingLinks(
            "<div>A&nbsp;&amp;&nbsp;B &#64; &#x43;o&mdash;end</div>"
        )

        XCTAssertEqual(stripped, "A & B @ Co—end")
    }

    func testHTMLStripConvertsBlockTagsToNewlines() {
        let stripped = htmlTagsStrippedForMeetingLinks("<p>First line</p><p>Second line</p>")

        XCTAssertEqual(stripped, "First line\nSecond line")
    }

    func testHTMLStripDoesNotLeakMachPorts() {
        // Regression guard for the EXC_GUARD mach-port exhaustion crash:
        // NSAttributedString(html:) leaked ~2 mach ports per call via TextKit's
        // nsattributedstringagent XPC service. The pure-Foundation strip must
        // allocate none. Reintroducing the XPC-backed parser makes the port
        // table grow ~800 over this loop and fails the assertion.
        let html = "<p>Join <a href=\"https://x\">https://us02web.zoom.us/j/1?a=1&amp;b=2</a></p>"
        _ = htmlTagsStrippedForMeetingLinks(html) // warm up any one-time caches

        let before = machPortCount()
        for _ in 0..<400 {
            _ = htmlTagsStrippedForMeetingLinks(html)
        }
        let after = machPortCount()

        XCTAssertGreaterThanOrEqual(before, 0, "mach_port_names failed")
        XCTAssertGreaterThanOrEqual(after, 0, "mach_port_names failed")
        let growth = after - before

        XCTAssertLessThan(
            growth, 100,
            "HTML stripping leaked \(growth) mach ports over 400 calls — an XPC-backed parser was reintroduced"
        )
    }

    private func machPortCount() -> Int {
        var names: mach_port_name_array_t?
        var namesCount: mach_msg_type_number_t = 0
        var types: mach_port_type_array_t?
        var typesCount: mach_msg_type_number_t = 0
        guard mach_port_names(mach_task_self_, &names, &namesCount, &types, &typesCount) == KERN_SUCCESS
        else { return -1 }
        return Int(namesCount)
    }

    func testCleanupOutlookSafeLinksUnwrapsValidLink() {
        let target = "https://zoom.us/j/123456789"
        let safe = outlookSafeLink(for: target)

        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: "Join \(safe) today"), "Join \(target) today")
    }

    func testCleanupOutlookSafeLinksTerminatesOnUndecodableTarget() {
        // Regression: a SafeLink whose `url=` value contains an invalid percent
        // escape ("%xx") makes `removingPercentEncoding` return nil, so the old
        // `repeat … while !links.isEmpty` loop never rewrote the text and spun
        // forever — wedging calendar sync on a single malformed event. The
        // cleanup must now terminate (test would hang/time out if it regressed).
        let malformed = "Join https://nam11.safelinks.protection.outlook.com/" +
            "?data=x&url=https%3A%2F%2Fzoom.us%2Fj%2F1%xx end"

        let result = cleanupOutlookSafeLinks(rawText: malformed)

        // Undecodable target is left untouched, but crucially the call returns.
        XCTAssertEqual(result, malformed)
    }

    func testCleanupOutlookSafeLinksTerminatesWhenRewriteMakesNoProgress() {
        // A SafeLink whose decoded `url=` value still contains the same SafeLink
        // (self-referential) must not loop forever.
        let selfReferential = "https://nam11.safelinks.protection.outlook.com/" +
            "?url=https://nam11.safelinks.protection.outlook.com/?url=x"

        let result = cleanupOutlookSafeLinks(rawText: selfReferential)

        // Terminates, fully unwrapping the nested wrappers to the inner target
        // rather than looping on the self-reference.
        XCTAssertEqual(result, "x")
    }

    func testDetectionSucceedsForEventCarryingUndecodableSafeLink() {
        // The end-to-end path that hung in the field: an event whose notes carry
        // a malformed SafeLink must still produce a detection result (here: the
        // plain Zoom link present alongside it) without hanging.
        let notes = "Backup https://nam11.safelinks.protection.outlook.com/" +
            "?data=x&url=https%3A%2F%2Fbad%xx\nReal: https://zoom.us/j/9999"

        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: notes,
            calendarEmail: nil,
            currentUserEmail: nil
        )

        XCTAssertEqual(link?.service, .zoom)
    }
}
