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
    MeetingLink(service: .zoom, url: URL(string: "https://any-client.zoom-x.de/j/65194487075")!),
    MeetingLink(service: .zoom_native, url: URL(string: "zoommtg://zoom.us/join?confno=123456789&pwd=xxxx&zc=0&browser=chrome&uname=Betty")!),
    MeetingLink(service: .zoom_native, url: URL(string: "zoommtg://zoom-x.de/join?confno=123456789&pwd=xxxx&zc=0&browser=chrome&uname=Betty")!),
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
    MeetingLink(service: .meetStream, url: URL(string: "https://stream.meet.google.com/stream/abc12ab1-abc1-1234-123a-a1234a1abc12")!),
    MeetingLink(service: .userzoom, url: URL(string: "https://go.userzoom.com/participate/12345xxx-1000-1234-1234-1234-12345xxx")!),
    MeetingLink(service: .venue, url: URL(string: "https://app.venue.live/app/sdoakdsakdas?token=kndsfglksnd21")!),
    MeetingLink(service: .teemyco, url: URL(string: "https://app.teemyco.com/room/7HAQH0keHU0uppUKmL7Z/goOvj4BlHSH1IkgOtaA0")!),
    MeetingLink(service: .demodesk, url: URL(string: "https://demodesk.com/NGYLHDWO")!),
    MeetingLink(service: .zoho_cliq, url: URL(string: "https://cliq.zoho.eu/meetings/alsfsma213")!),
    MeetingLink(service: .slack, url: URL(string: "https://app.slack.com/huddle/T01ABCDEFGH/C02ABCDEFGH")!),
    MeetingLink(service: .gather, url: URL(string: "https://app.gather.town/app/1a2S3d4F5G/1a2S-3d4F_5G6h?spawnToken=1a2S3d4F5G")!),
    MeetingLink(service: .gather, url: URL(string: "https://app.gather.town/app/1a2S3d4F5G/1a2S-3d4F_5G6h?meeting=1a2S3d4F5G")!),
    MeetingLink(service: .vimeo, url: URL(string: "https://venues.vimeo.com/12345678/abcdef123")!),
    MeetingLink(service: .reclaim, url: URL(string: "https://reclaim.ai/z/T01ABCDEFGH/C02ABCDEFGH")!),
    MeetingLink(service: .tuple, url: URL(string: "https://tuple.app/c/V1StGXR8_Z5jdHi6B")!),
    MeetingLink(service: .pumble, url: URL(string: "https://meet.pumble.com/vly-hggs-xsn")!),
    MeetingLink(service: .suitConference, url: URL(string: "https://turkcell.conference.istesuit.com/username")!),
    MeetingLink(service: .doxyMe, url: URL(string: "https://bbc.doxy.me/dr.who")!)
]

class MeetingServicesTests: XCTestCase {
    func testDetectMeetingLink() throws {
        for meeting in meetings {
            let result = detectMeetingLink(meeting.url.absoluteString)
            XCTAssertNotNil(result)
            XCTAssertEqual(result, meeting)
        }
    }
}
