//
//  EKEventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit
import PromiseKit

// Ref: https://stackoverflow.com/a/66074963
extension EKParticipant {
    public var safeURL: URL? {
        perform(#selector(getter: EKParticipant.url))?.takeUnretainedValue() as? NSURL? as? URL
    }
}

extension EKEventStore: EventStore {
    static let shared = initEKEventStore()

    var isAuthed: Bool {
        EKEventStore.authorizationStatus(for: .event) == .authorized
    }

    func signIn() -> Promise<Void> {
        Promise { seal in
            EKEventStore.shared.requestAccess(to: .event) { granted, _ in
                if granted {
                    seal.fulfill(())
                } else {
                    seal.reject(NSError())
                }
            }
        }
    }

    func signOut() -> Promise<Void> {
        Promise { _ in }
    }

    func refreshSources() {
        EKEventStore.shared.refreshSourcesIfNecessary()
    }

    func fetchAllCalendars() -> Promise<[MBCalendar]> {
        Promise { seal in
            var allCalendars: [MBCalendar] = []

            for calendar in EKEventStore.shared.calendars(for: .event) {
                let calendar = MBCalendar(title: calendar.title, ID: calendar.calendarIdentifier, source: calendar.source.title, email: _getGmailAccount(calendar.source.description), color: calendar.color)
                allCalendars.append(calendar)
            }
            return seal.fulfill(allCalendars)
        }
    }

    func fetchEventsForDateRange(calendars: [MBCalendar], dateFrom: Date, dateTo: Date) -> Promise<[MBEvent]> {
        Promise { seal in
            let selectedCalendars = EKEventStore.shared.calendars(for: .event).filter { calendars.map(\.ID).contains($0.calendarIdentifier) }

            if selectedCalendars.isEmpty {
                return seal.fulfill([])
            }

            let predicate = predicateForEvents(withStart: dateFrom, end: dateTo, calendars: selectedCalendars)

            var events: [MBEvent] = []
            for rawEvent in EKEventStore.shared.events(matching: predicate) {
                let calendar = calendars.first(where: { $0.ID == rawEvent.calendar.calendarIdentifier })!

                var status: MBEventStatus
                switch rawEvent.status {
                case .confirmed:
                    status = .confirmed
                case .tentative:
                    status = .tentative
                case .canceled:
                    status = .canceled
                default:
                    status = .none
                }

                let organizer = MBEventOrganizer(email: rawEvent.organizer?.url.absoluteString, name: rawEvent.organizer?.name)

                var attendees: [MBEventAttendee] = []

                for rawAttendee in rawEvent.attendees ?? [] {
                    if rawAttendee.participantType != .person {
                        continue
                    }
                    var attendeeStatus: MBEventAttendeeStatus
                    switch rawAttendee.participantStatus {
                    case .pending:
                        attendeeStatus = .pending
                    case .accepted:
                        attendeeStatus = .accepted
                    case .declined:
                        attendeeStatus = .declined
                    case .tentative:
                        attendeeStatus = .tentative
                    case .delegated:
                        attendeeStatus = .delegated
                    case .completed:
                        attendeeStatus = .completed
                    case .inProcess:
                        attendeeStatus = .inProcess
                    default:
                        attendeeStatus = .unknown
                    }

                    let optional = rawAttendee.participantRole == .optional
                    let email = rawAttendee.safeURL?.absoluteString
                    let attendee = MBEventAttendee(email: email, name: rawAttendee.name, status: attendeeStatus, optional: optional, isCurrentUser: rawAttendee.isCurrentUser)

                    attendees.append(attendee)
                }

                let event = MBEvent(
                    ID: rawEvent.calendarItemIdentifier, lastModifiedDate: rawEvent.lastModifiedDate,
                    title: rawEvent.title, status: status, notes: rawEvent.notes, location: rawEvent.location,
                    url: rawEvent.url, organizer: organizer, attendees: attendees,
                    startDate: rawEvent.startDate, endDate: rawEvent.endDate,
                    isAllDay: rawEvent.isAllDay, recurrent: rawEvent.hasRecurrenceRules, calendar: calendar
                )
                events.append(event)
            }
            seal.fulfill(events)
        }
    }
}

func initEKEventStore() -> EKEventStore {
    let eventStore = EKEventStore()

    var sources = eventStore.sources
    sources.append(contentsOf: eventStore.delegateSources)

    return EKEventStore(sources: sources)
}

func _getGmailAccount(_ text: String) -> String? {
    // Hacky and likely to break, but should work until Apple changes something
    let regex = try! NSRegularExpression(pattern: #""mailto:(.+@.+)""#)
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range(at: 1), in: text)!]) }
    if !resultsMap.isEmpty {
        return resultsMap.first
    }
    return nil
}
