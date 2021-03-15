//
//  MeetingBarTests.swift
//  MeetingBarTests
//
//  Created by Andrii Leitsius on 28.02.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import XCTest
import EventKit

@testable import MeetingBar


let meetings = [
    MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/5551112222")!),
    MeetingLink(service: .zoom_native, url: URL(string: "zoommtg://zoom.us/join?confno=123456789&pwd=xxxx&zc=0&browser=chrome&uname=Betty")!),
    MeetingLink(service: .around, url: URL(string: "https://meet.around.co/r/kyafvk1b")!)
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
