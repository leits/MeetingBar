//
//  MeetingOpeningPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class MeetingOpeningPolicyTests: XCTestCase {
    private let meetingURL = URL(string: "https://meet.google.com/abc-defg-hij")!
    private let eventURL = URL(string: "https://calendar.example.test/event")!

    func testMeetingLinkWinsOverEventURLAndRunsJoinScriptWhenEnabled() {
        let meetingLink = MeetingLink(service: .meet, url: meetingURL)
        let action = MeetingOpeningPolicy.action(
            for: MeetingOpeningEvent(
                title: "Standup",
                meetingLink: meetingLink,
                eventURL: eventURL
            ),
            runJoinEventScript: true
        )

        XCTAssertEqual(action, .openMeetingLink(meetingLink, runJoinScript: true))
    }

    func testMeetingLinkDoesNotRunJoinScriptWhenDisabled() {
        let meetingLink = MeetingLink(service: .zoom, url: meetingURL)
        let action = MeetingOpeningPolicy.action(
            for: MeetingOpeningEvent(
                title: "Standup",
                meetingLink: meetingLink,
                eventURL: nil
            ),
            runJoinEventScript: false
        )

        XCTAssertEqual(action, .openMeetingLink(meetingLink, runJoinScript: false))
    }

    func testEventURLIsFallbackWhenMeetingLinkMissing() {
        let action = MeetingOpeningPolicy.action(
            for: MeetingOpeningEvent(
                title: "Standup",
                meetingLink: nil,
                eventURL: eventURL
            ),
            runJoinEventScript: true
        )

        XCTAssertEqual(action, .openEventURL(eventURL))
    }

    func testMissingLinksProduceMissingLinkNotificationAction() {
        let action = MeetingOpeningPolicy.action(
            for: MeetingOpeningEvent(
                title: "Standup",
                meetingLink: nil,
                eventURL: nil
            ),
            runJoinEventScript: true
        )

        XCTAssertEqual(action, .notifyMissingLink(title: "Standup"))
    }
}
