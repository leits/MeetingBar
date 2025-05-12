//
//  Event.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 09.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults

public enum MBEventStatus: Int, Sendable {
    case none = 0
    case confirmed = 1
    case tentative = 2
    case canceled = 3
}

public struct MBEventOrganizer: Hashable, Sendable {
    let name: String
    let email: String?

    init(email: String? = nil, name: String?) {
        self.email = email
        self.name = name ?? email ?? "status_bar_submenu_attendees_no_name".loco()
    }
}

public enum MBEventAttendeeStatus: Int, Sendable {
    case unknown = 0
    case pending = 1
    case accepted = 2
    case declined = 3
    case tentative = 4
    case delegated = 5
    case completed = 6
    case inProcess = 7
}

public struct MBEventAttendee: Hashable, Sendable {
    public let name: String
    public let email: String?
    public let status: MBEventAttendeeStatus
    public var optional = false
    public let isCurrentUser: Bool

    init(email: String?, name: String? = nil, status: MBEventAttendeeStatus, optional: Bool = false, isCurrentUser: Bool = false) {
        self.email = email
        self.name = name ?? email ?? "status_bar_submenu_attendees_no_name".loco()
        self.status = status
        self.optional = optional
        self.isCurrentUser = isCurrentUser
    }
}

// ToDo: move to struct
public struct MBEvent: Identifiable, Hashable, Sendable {
    public var id: String

    public let lastModifiedDate: Date?
    public let calendar: MBCalendar
    public let title: String
    public var status: MBEventStatus
    public var participationStatus: MBEventAttendeeStatus = .unknown
    public var meetingLink: MeetingLink?
    public var organizer: MBEventOrganizer?
    public let url: URL?
    public let notes: String?
    public let location: String?
    public let startDate: Date
    public let endDate: Date
    public var isAllDay: Bool
    public let recurrent: Bool
    public var attendees: [MBEventAttendee] = []

    init(id: String,
         lastModifiedDate: Date?,
         title: String?,
         status: MBEventStatus,
         notes: String?,
         location: String?,
         url: URL?,
         organizer: MBEventOrganizer?,
         attendees: [MBEventAttendee] = [],
         startDate: Date,
         endDate: Date,
         isAllDay: Bool,
         recurrent: Bool,
         calendar: MBCalendar) {
        self.calendar = calendar
        self.id = id
        self.lastModifiedDate = lastModifiedDate
        self.title = title ?? "status_bar_no_title".loco()
        self.status = status

        self.isAllDay = isAllDay
        if !isAllDay, startDate != endDate {
            // Treat events from midnight to midnight as an all-day event
            let startDateIsMidnight = Calendar.current.startOfDay(for: startDate) == startDate
            let endDateIsMidnight = Calendar.current.startOfDay(for: endDate) == endDate
            if startDateIsMidnight, endDateIsMidnight {
                self.isAllDay = true
            }
        }

        self.notes = notes
        self.location = location
        self.url = url

        self.organizer = organizer
        self.attendees = attendees
        self.startDate = startDate
        self.endDate = endDate
        self.recurrent = recurrent

        if let currentUser = attendees.first(where: { $0.isCurrentUser }) {
            participationStatus = currentUser.status
        }

        let linkFields = [
            location,
            url?.absoluteString,
            notes,
            notes?.htmlTagsStripped()
        ].compactMap { $0 }

        for linkField in linkFields {
            if var detectedLink = detectMeetingLink(linkField) {
                if detectedLink.service == .meet,
                   let authAccount = calendar.email ?? attendees.first(where: { $0.isCurrentUser })?.email,
                   let urlEncodedAccount = authAccount.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
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
                    let task = try? NSUserAppleScriptTask(url: url)
                    task?.execute { error in
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

func getEventDateString(_ event: MBEvent) -> String {
    let eventTimeFormatter = DateFormatter()
    eventTimeFormatter.locale = I18N.instance.locale

    switch Defaults[.timeFormat] {
    case .am_pm:
        eventTimeFormatter.dateFormat = "h:mm a  "
    case .military:
        eventTimeFormatter.dateFormat = "HH:mm"
    }
    let eventStartTime = eventTimeFormatter.string(from: event.startDate)
    let eventEndTime = eventTimeFormatter.string(from: event.endDate)
    let eventDurationMinutes = String(Int(event.endDate.timeIntervalSince(event.startDate) / 60))
    let durationTitle = "status_bar_submenu_duration_all_day".loco(eventStartTime, eventEndTime, eventDurationMinutes)
    return durationTitle
}
