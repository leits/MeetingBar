//
//  MeetingBarTests.swift
//  MeetingBarTests
//
//  Created by Andrii Leitsius on 28.02.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import EventKit
import XCTest

@testable import MeetingBar

let meetings = [
    MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/5551112222")!),
    MeetingLink(service: .zoom_native, url: URL(string: "zoommtg://zoom.us/join?confno=123456789&pwd=xxxx&zc=0&browser=chrome&uname=Betty")!),
    MeetingLink(service: .around, url: URL(string: "https://meet.around.co/r/kyafvk1b")!),
    MeetingLink(service: .blackboard_collab, url: URL(string: "https://us.bbcollab.com/guest/C2419D0F68382D351B97376D6B47ABA2")!),
    MeetingLink(service: .blackboard_collab, url: URL(string: "https://us.bbcollab.com/invite/EFC53F2790E6E50FFCC2AFBC16CC69EE")!),
    MeetingLink(service: .coscreen, url: URL(string: "https://join.coscreen.co/Eng-Leads/95RyHqtzn7EoQjQ19ju3")!),
    MeetingLink(service: .ovice, url: URL(string: "https://universeph-armynight.ovice.in/lobby/enter")!),
]

class HelpersTests: XCTestCase {
    func testGetMeetingLink() throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents

        for meeting in meetings {
            event.notes = meeting.url.absoluteString
            let result = getMeetingLink(event)

            XCTAssertNotNil(result)
            XCTAssertEqual(result, meeting)
        }
    }
}
