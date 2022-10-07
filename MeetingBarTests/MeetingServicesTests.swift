//
//  MeetingServicesTests.swift
//  MeetingBarTests
//
//  Created by Andrii Leitsius on 28.02.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import XCTest

@testable import MeetingBar

let meetings = [
    MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/5551112222")!),
    MeetingLink(service: .zoom_native, url: URL(string: "zoommtg://zoom.us/join?confno=123456789&pwd=xxxx&zc=0&browser=chrome&uname=Betty")!),
    MeetingLink(service: .around, url: URL(string: "https://meet.around.co/r/kyafvk1b")!),
    MeetingLink(service: .around, url: URL(string: "https://around.co/r/kyafvk1b")!),
    MeetingLink(service: .blackboard_collab, url: URL(string: "https://us.bbcollab.com/guest/C2419D0F68382D351B97376D6B47ABA2")!),
    MeetingLink(service: .blackboard_collab, url: URL(string: "https://us.bbcollab.com/invite/EFC53F2790E6E50FFCC2AFBC16CC69EE")!),
    MeetingLink(service: .coscreen, url: URL(string: "https://join.coscreen.co/Eng-Leads/95RyHqtzn7EoQjQ19ju3")!),
    MeetingLink(service: .ovice, url: URL(string: "https://universeph-armynight.ovice.in/lobby/enter")!),
    MeetingLink(service: .facetime, url: URL(string: "https://facetime.apple.com/join#v=1&p=AeVKu1rGEeyppwJC8kftBg&k=FrCNneouFgL26VdnDit78WHNoGjzZyteymBi1U5I23E")!),
    MeetingLink(service: .pop, url: URL(string: "https://pop.com/j/810-218-630")!),
    MeetingLink(service: .gong, url: URL(string: "https://join.gong.io/mycompany/ryker.morgan")!),
    MeetingLink(service: .chorus, url: URL(string: "https://go.chorus.ai/1234567890")!),
    MeetingLink(service: .livestorm, url: URL(string: "https://app.livestorm.com/p/cc113fd5-5de1-406-ba74-85c4892530/live?s=0231a8fb-fce9-48b0-9263-525f4234234234")!),
    MeetingLink(service: .preply, url: URL(string: "https://preply.com/ua/chat/t-room/3262947?source=email_calendar")!),
]

class MeetingServicesTests: XCTestCase {
    func test_detectMeetingLink() throws {
        for meeting in meetings {
            let result = detectMeetingLink(meeting.url.absoluteString)
            XCTAssertNotNil(result)
            XCTAssertEqual(result, meeting)
        }
    }
}
