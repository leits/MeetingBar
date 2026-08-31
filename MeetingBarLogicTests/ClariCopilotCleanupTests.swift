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
        // Any suffix after the code means the slug is not a Meet code; a
        // partial rewrite would point at the wrong meeting.
        for slug in ["abc-defg-hijk", "abc-defg-hij1", "abc-defg-hij_x", "abc-defg-hijX"] {
            let text = "https://go.copilot.clari.com/hangout/\(slug)"
            XCTAssertEqual(cleanupClariCopilotLinks(rawText: text), text)
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
}
