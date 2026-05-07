//
//  MBEvent.swift
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

public struct MBEvent: Identifiable, Hashable, Sendable {
    public var id: String

    public let lastModifiedDate: Date?
    public let calendar: MBCalendar
    public let title: String
    public var status: MBEventStatus
    public var participationStatus: MBEventAttendeeStatus = .unknown
    public var meetingLink: MeetingLink?
    var meetingLinkCandidate: MeetingLinkCandidate?
    var alternateMeetingLinkCandidates: [MeetingLinkCandidate] = []
    public var organizer: MBEventOrganizer?
    public let url: URL?
    /// Structured meeting URL exposed by the provider (e.g. Google Calendar's
    /// `conferenceData.entryPoints[type=video]`). When set, this beats links
    /// found in `url`, `location`, or `notes` regardless of what those fields
    /// contain. EventKit has no equivalent, so this is `nil` for those events.
    public let conferenceURL: URL?
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
         conferenceURL: URL? = nil,
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
        self.conferenceURL = conferenceURL

        self.organizer = organizer
        self.attendees = attendees
        self.startDate = startDate
        self.endDate = endDate
        self.recurrent = recurrent

        let currentUser = attendees.first(where: { $0.isCurrentUser })
        if let currentUser {
            participationStatus = currentUser.status
        }

        let meetingLinkCandidates = MeetingLinkDetector.allCandidates(
            conferenceURL: conferenceURL,
            location: location,
            eventURL: url,
            notes: notes,
            calendarEmail: calendar.email,
            currentUserEmail: currentUser?.email,
            customRegexes: Defaults[.customRegexes]
        )
        meetingLinkCandidate = meetingLinkCandidates.first
        alternateMeetingLinkCandidates = Array(meetingLinkCandidates.dropFirst())
        if let meetingLinkCandidate {
            meetingLink = MeetingLink(service: meetingLinkCandidate.service, url: meetingLinkCandidate.url)
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
        MeetingOpener.open(event: self)
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

// MARK: - Filtering / next-event helpers

public extension Array where Element == MBEvent {
    /// Returns only those events that pass all the user's Defaults filters.
    func filtered() -> [MBEvent] {
        let candidates = enumerated().map { index, event in
            EventFilterEvent(event: event, sourceIndex: index)
        }
        return EventFiltering
            .filter(candidates, settings: .current)
            .map { self[$0.sourceIndex] }
    }

    /// From a pre-filtered, sorted array, find the nearest upcoming MBEvent.
    func nextEvent(linkRequired: Bool = false) -> MBEvent? {
        let candidates = enumerated().map { index, event in
            EventSelectionEvent(event: event, sourceIndex: index)
        }
        guard let selected = EventSelection.nextEvent(
            from: candidates,
            linkRequired: linkRequired,
            settings: .current,
            now: Date()
        ) else {
            return nil
        }
        return self[selected.sourceIndex]
    }
}
