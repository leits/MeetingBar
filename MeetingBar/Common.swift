//
//  Common.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.03.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults
import PromiseKit
import SwiftyJSON

protocol EventStore {
    var isAuthed: Bool { get }

    func signIn() -> Promise<Void>

    func signOut() -> Promise<Void>

    func fetchAllCalendars() -> Promise<[MBCalendar]>

    func fetchEventsForDateRange(calendars: [MBCalendar], dateFrom: Date, dateTo: Date) -> Promise<[MBEvent]>
}

class MBCalendar: Hashable {
    let title: String
    let ID: String
    let source: String
    let email: String?
    var selected: Bool = false
    let color: NSColor

    init(title: String, ID: String, source: String?, email: String?, color: NSColor) {
        self.title = title
        self.ID = ID
        self.source = source ?? "unknown"
        self.email = email
        self.color = color
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ID)
    }

    static func == (lhs: MBCalendar, rhs: MBCalendar) -> Bool {
        lhs.ID == rhs.ID
    }
}

enum MBEventStatus: Int {
    case none = 0
    case confirmed = 1
    case tentative = 2
    case canceled = 3
}

class MBEventOrganizer {
    let name: String
    let email: String?

    init(email: String? = nil, name: String?) {
        self.email = email
        self.name = name ?? email ?? "status_bar_submenu_attendees_no_name".loco()
    }
}

enum MBEventAttendeeStatus: Int {
    case unknown = 0
    case pending = 1
    case accepted = 2
    case declined = 3
    case tentative = 4
    case delegated = 5
    case completed = 6
    case inProcess = 7
}

class MBEventAttendee {
    let name: String
    let email: String?
    let status: MBEventAttendeeStatus
    var optional: Bool = false
    let isCurrentUser: Bool

    init(email: String?, name: String? = nil, status: MBEventAttendeeStatus, optional: Bool = false, isCurrentUser: Bool = false) {
        self.email = email
        self.name = name ?? email ?? "status_bar_submenu_attendees_no_name".loco()
        self.status = status
        self.optional = optional
        self.isCurrentUser = isCurrentUser
    }
}

class MBEvent {
    let ID: String
    let calendar: MBCalendar
    let title: String
    var status: MBEventStatus
    var participationStatus: MBEventAttendeeStatus = .unknown
    var meetingLink: MeetingLink?
    var organizer: MBEventOrganizer?
    let url: URL?
    let notes: String?
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    var attendees: [MBEventAttendee] = []

    init(ID: String, title: String?, status: MBEventStatus, notes: String?, location: String?, url: URL?, organizer: MBEventOrganizer?, attendees: [MBEventAttendee] = [], startDate: Date, endDate: Date, isAllDay: Bool, calendar: MBCalendar) {
        self.calendar = calendar
        self.ID = ID
        self.title = title ?? "status_bar_no_title".loco()
        self.status = status

        self.notes = notes
        self.location = location
        self.url = url

        self.organizer = organizer
        self.attendees = attendees
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay

        if let currentUser = attendees.first(where: { $0.isCurrentUser }) {
            participationStatus = currentUser.status
        }

        let linkFields = [
            location,
            url?.absoluteString,
            notes,
        ].compactMap { $0 }

        for linkField in linkFields {
            if var detectedLink = detectLink(linkField) {
                if detectedLink.service == .meet,
                   let account = getEmailAccount(calendar.source),
                   let urlEncodedAccount = account.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                {
                    detectedLink.url = URL(string: (detectedLink.url.absoluteString) + "?authuser=\(urlEncodedAccount)")!
                }
                meetingLink = detectedLink
                break
            }
        }
    }
}

func filterEvents(_ events: [MBEvent]) -> [MBEvent] {
    var filteredCalendarEvents: [MBEvent] = []

    for calendarEvent in events {
        // Filter events base on custom user regexes
        for pattern in Defaults[.filterEventRegexes] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                if !hasMatch(text: calendarEvent.title, regex: regex) {
                    continue
                }
            }
        }

        if calendarEvent.isAllDay {
            // Filter all day events
            switch Defaults[.allDayEvents] {
            case .show:
                break
            case .show_with_meeting_link_only:
                if calendarEvent.meetingLink?.url == nil { continue } // Skip this event
            case .hide:
                continue // Skip this event
            }
        } else {
            // Filter not for all day events
            switch Defaults[.nonAllDayEvents] {
            case .show, .show_inactive_without_meeting_link:
                break
            case .hide_without_meeting_link:
                if calendarEvent.meetingLink?.url == nil { continue } // Skip this event
            }
        }

        // Filter pending events
        switch Defaults[.showPendingEvents] {
        case .show, .show_inactive, .show_underlined:
            break
        case .hide:
            if calendarEvent.participationStatus == .pending { continue } // Skip this event
        }

        filteredCalendarEvents.append(calendarEvent)
    }
    return filteredCalendarEvents
}
