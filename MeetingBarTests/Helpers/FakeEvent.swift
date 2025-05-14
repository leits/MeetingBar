//
//  FakeEvent.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import Foundation
@testable import MeetingBar

// Helper to construct a minimal MBEvent – adjust to your real initializer
func makeFakeEvent(
    id: String,
    start: Date,
    end: Date,
    isAllDay: Bool = false,
    status: MBEventStatus = .confirmed,
    withLink: Bool = false,
    participationStatus: MBEventAttendeeStatus = .accepted
) -> MBEvent {

    let calendar = MBCalendar(title: "Fake calendar \(id)", id: "cal_\(id)", source: nil, email: nil, color: .black)

    let link = withLink ? URL(string: "https://zoom.us/j/5551112222")! : nil
    var event = MBEvent(
        id: id,
        lastModifiedDate: Date(),
        title: "Event \(id)",
        status: .confirmed,
        notes: nil,
        location: nil,
        url: link,
        organizer: nil,
        startDate: start,
        endDate: end,
        isAllDay: isAllDay,
        recurrent: false,
        calendar: calendar
    )
    event.participationStatus = participationStatus
    return event
}
