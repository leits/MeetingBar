//
//  Event.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 09.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults

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

    func emailAttendees() {
        let service = NSSharingService(named: NSSharingService.Name.composeEmail)!
        var recipients: [String] = []
        for attendee in attendees {
            if let email = attendee.email {
                recipients.append(email)
            }
        }
        service.recipients = recipients
        service.subject = title
        service.perform(withItems: [])
    }

    func openMeeting() {
        if let meetingLink = meetingLink {
            if Defaults[.runJoinEventScript], Defaults[.joinEventScriptLocation] != nil {
                if let url = Defaults[.joinEventScriptLocation]?.appendingPathComponent("joinEventScript.scpt") {
                    let task = try! NSUserAppleScriptTask(url: url)
                    task.execute { error in
                        if let error = error {
                            sendNotification("status_bar_error_apple_script_title".loco(), error.localizedDescription)
                        }
                    }
                }
            }
            openMeetingURL(meetingLink.service, meetingLink.url, nil)
        } else if let eventUrl = url {
            eventUrl.openInDefaultBrowser()
        } else {
            sendNotification("status_bar_error_link_missed_title".loco(title), "status_bar_error_link_missed_message".loco())
        }
    }
}

func filterEvents(_ events: [MBEvent]) -> [MBEvent] {
    var filteredCalendarEvents: [MBEvent] = []

    for calendarEvent in events {
        // Filter events base on custom user regexes
        for pattern in Defaults[.filterEventRegexes] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let hasMatch = regex.firstMatch(in: calendarEvent.title, range: NSRange(calendarEvent.title.startIndex..., in: calendarEvent.title)) != nil
                if !hasMatch {
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

func getNextEvent(events: [MBEvent]) -> MBEvent? {
    var nextEvent: MBEvent?

    let now = Date()
    let startPeriod = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
    var endPeriod: Date

    let todayMidnight = Calendar.current.startOfDay(for: now)
    switch Defaults[.showEventsForPeriod] {
    case .today:
        endPeriod = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!
    case .today_n_tomorrow:
        endPeriod = Calendar.current.date(byAdding: .day, value: 2, to: todayMidnight)!
    }

    var nextEvents = events.filter { $0.endDate > startPeriod && $0.startDate < endPeriod }

    // Filter out personal events, if not marked as 'active'
    if Defaults[.personalEventsAppereance] != .show_active {
        nextEvents = nextEvents.filter { $0.attendees.count > 0 }
    }

    // If the current event is still going on,
    // but the next event is closer than 13 minutes later
    // then show the next event
    for event in nextEvents {
        if event.isAllDay {
            continue
        } else {
            if Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.show_inactive_without_meeting_link {
                if event.meetingLink == nil {
                    continue
                }
            } else if Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.hide_without_meeting_link {
                if event.meetingLink?.url == nil {
                    continue
                }
            }
        }

        if event.participationStatus == .declined { // Skip event if declined
            continue
        }

        if event.participationStatus == .pending, Defaults[.showPendingEvents] == PendingEventsAppereance.hide || Defaults[.showPendingEvents] == PendingEventsAppereance.show_inactive {
            continue
        }

        if event.status == .canceled {
            continue
        } else {
            if nextEvent == nil {
                nextEvent = event
                continue
            } else {
                let soon = now.addingTimeInterval(780) // 13 min from now
                if event.startDate < soon {
                    nextEvent = event
                } else {
                    break
                }
            }
        }
    }
    return nextEvent
}
