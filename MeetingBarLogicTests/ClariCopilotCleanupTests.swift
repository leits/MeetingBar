//
//  ClariCopilotCleanupTests.swift
//  MeetingBar
//

import XCTest
@testable import MeetingBarLogic

final class ClariCopilotCleanupTests: XCTestCase {
    func testRewritesWrapperToDirectMeetLink() {
        let out = cleanupClariCopilotLinks(
            rawText: "Join: https://go.copilot.clari.com/hangout/abc-defg-hij/")

        XCTAssertEqual(out, "Join: https://meet.google.com/abc-defg-hij")
    }

    func testLeavesNonMeetCodeSlugsAlone() {
        // A longer slug or a deeper path is not a Meet code link; a partial
        // rewrite would point at the wrong meeting.
        for slug in [
            "abc-defg-hijk", "abc-defg-hij1", "abc-defg-hij_x", "abc-defg-hijX",
            "abc-defg-hij/notes", "abc-defg-hij+suffix", "abc-defg-hij;extra",
            "abc-defg-hij=value", "abc-defg-hij:extra", "abc-defg-hij@extra",
            "abc-defg-hij!extra", "abc-defg-hij$extra", "abc-defg-hij&extra",
            "abc-defg-hijé", "abc-defg-hij/+suffix", "abc-defg-hij/;extra"
        ] {
            let text = "https://go.copilot.clari.com/hangout/\(slug)"
            XCTAssertEqual(cleanupClariCopilotLinks(rawText: text), text)
            XCTAssertNil(detectMeetingLink(text))
        }
    }

    func testAcceptsOnlyCompletePathsBeforeURLOrTextDelimiters() {
        for slash in ["", "/"] {
            for suffix in ["?source=calendar", "#details", " next", "\nnext", "\"", "'", ">"] {
                let wrapper = "https://go.copilot.clari.com/hangout/abc-defg-hij\(slash)\(suffix)"
                XCTAssertEqual(
                    cleanupClariCopilotLinks(rawText: wrapper),
                    "https://meet.google.com/abc-defg-hij\(suffix)"
                )
                XCTAssertEqual(detectMeetingLink(wrapper)?.service, .meet)
            }
        }
    }

    func testLeavesOtherClariPathsAlone() {
        let text = "https://go.copilot.clari.com/zoom/12345"
        XCTAssertEqual(cleanupClariCopilotLinks(rawText: text), text)
    }

    func testWrapperIsDetectedAsGoogleMeet() {
        let link = detectMeetingLink("https://go.copilot.clari.com/hangout/abc-defg-hij/")

        XCTAssertEqual(link?.service, .meet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testWrapperInsideOutlookSafeLinkIsUnwrappedFirst() {
        let wrapped = "https://eur04.safelinks.protection.outlook.com/?url="
            + "https%3A%2F%2Fgo.copilot.clari.com%2Fhangout%2Fabc-defg-hij%2F"

        let link = detectMeetingLink(wrapped)

        XCTAssertEqual(link?.service, .meet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testConferenceDataWrapperYieldsDirectMeetURLWithAuthuser() {
        // The wrapper must be rewritten before the candidate is built, or
        // authuser (the account email) would be appended to the Clari host.
        let candidate = MeetingLinkDetector.bestCandidate(
            conferenceURL: URL(string: "https://go.copilot.clari.com/hangout/abc-defg-hij/")!,
            location: nil,
            eventURL: nil,
            notes: nil,
            calendarEmail: "user@example.com",
            currentUserEmail: nil
        )

        XCTAssertEqual(candidate?.service, .meet)
        XCTAssertEqual(
            candidate?.url.absoluteString,
            "https://meet.google.com/abc-defg-hij?authuser=user@example.com")
    }

    func testCandidatesFromEventFieldsUseBaseGmailAccount() {
        let wrapper = "https://go.copilot.clari.com/hangout/abc-defg-hij/"
        for source in [MeetingLinkSource.eventURL, .location, .notes] {
            let candidate = MeetingLinkDetector.bestCandidate(
                location: source == .location ? wrapper : nil,
                eventURL: source == .eventURL ? URL(string: wrapper) : nil,
                notes: source == .notes ? wrapper : nil,
                calendarEmail: "user+work@gmail.com",
                currentUserEmail: nil
            )
            XCTAssertEqual(candidate?.source, source)
            XCTAssertEqual(candidate?.service, .meet)
            XCTAssertEqual(candidate?.url.absoluteString, "https://meet.google.com/abc-defg-hij?authuser=user@gmail.com")
        }
    }

    func testUnrelatedHostsAndDirectMeetingLinksAreUnchanged() {
        for text in [
            "https://example.com/hangout/abc-defg-hij",
            "https://go.copilot.clari.com.example.com/hangout/abc-defg-hij",
            "https://meet.google.com/abc-defg-hij",
            "https://zoom.us/j/123456789?pwd=secret"
        ] {
            XCTAssertEqual(cleanupClariCopilotLinks(rawText: text), text)
        }
    }


    func testSafeLinkedConferenceDataStoresDirectMeetURLWithAuthuser() {
        let wrapper = "https://eur04.safelinks.protection.outlook.com/?url="
            + "https%3A%2F%2Fgo.copilot.clari.com%2Fhangout%2Fabc-defg-hij%2F"
        let candidate = MeetingLinkDetector.bestCandidate(
            conferenceURL: URL(string: wrapper),
            location: nil, eventURL: nil, notes: nil,
            calendarEmail: "user@example.com", currentUserEmail: nil
        )
        XCTAssertEqual(candidate?.source, .providerConferenceData)
        XCTAssertEqual(candidate?.service, .meet)
        XCTAssertEqual(candidate?.url.absoluteString, "https://meet.google.com/abc-defg-hij?authuser=user@example.com")
    }

}
