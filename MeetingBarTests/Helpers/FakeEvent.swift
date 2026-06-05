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
    participationStatus: MBEventAttendeeStatus = .accepted,
    lastModifiedDate: Date? = nil,
    calendarOpenURL: URL? = nil,
    attendees: [MBEventAttendee] = []
) -> MBEvent {
    let calendar = MBCalendar(
        title: "Test Calendar",
        id: "cal_\(id)",
        source: nil,
        email: nil,
        color: .black
    )

    let link = withLink
        ? URL(string: "https://zoom.us/j/5551112222")!
        : nil

    var event = MBEvent(
        id: id,
        lastModifiedDate: lastModifiedDate ?? Date(),
        title: "Event \(id)",
        status: status,
        notes: nil,
        location: nil,
        url: link,
        calendarOpenURL: calendarOpenURL,
        organizer: nil,
        attendees: attendees,
        startDate: start,
        endDate: end,
        isAllDay: isAllDay,
        recurrent: false,
        calendar: calendar
    )
    event.participationStatus = participationStatus
    return event
}
