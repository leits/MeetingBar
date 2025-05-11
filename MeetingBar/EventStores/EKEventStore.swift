//
//  EKEventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit

// Ref: https://stackoverflow.com/a/66074963
extension EKParticipant {
    var safeNSURL: NSURL? {
        perform(#selector(getter: EKParticipant.url))?.takeUnretainedValue() as? NSURL
    }
}

extension EKEventStore: EventStore {
    nonisolated(unsafe) static var shared = EKEventStore()

    func signIn() async throws {
            try await withCheckedThrowingContinuation { cont in
                let handler: EKEventStoreRequestAccessCompletionHandler = { granted, error in
                    if granted {
                        var sources = EKEventStore.shared.sources
                        sources.append(contentsOf: EKEventStore.shared.delegateSources)

                        EKEventStore.shared = EKEventStore(sources: sources)
                        cont.resume()
                    } else { cont.resume(throwing: error ?? NSError(domain: "EKEventStore", code: 0)) }
                }

                if #available(macOS 14, *) {
                    EKEventStore.shared.requestFullAccessToEvents(completion: handler)
                } else {
                    EKEventStore.shared.requestAccess(to: .event, completion: handler)
                }
            }
        }

    func signOut() async {}

    func refreshSources() async {
        EKEventStore.shared.refreshSourcesIfNecessary()
    }

    func fetchAllCalendars() async throws -> [MBCalendar] {
        var allCalendars: [MBCalendar] = []

        for calendar in EKEventStore.shared.calendars(for: .event) {
            let calendar = MBCalendar(
                title: calendar.title,
                ID: calendar.calendarIdentifier,
                source: calendar.source.title,
                email: getGmailAccount(calendar.source.description),
                color: calendar.color
            )
            allCalendars.append(calendar)
        }
        return allCalendars
    }

    func fetchEventsForDateRange(for calendars: [MBCalendar], from dateFrom: Date, to dateTo: Date) async throws -> [MBEvent] {
        let selectedCalendars = EKEventStore.shared.calendars(for: .event).filter { calendars.map(\.ID).contains($0.calendarIdentifier) }

        if selectedCalendars.isEmpty {
            return []
        }

        let predicate = predicateForEvents(withStart: dateFrom, end: dateTo, calendars: selectedCalendars)

        var events: [MBEvent] = []
        for rawEvent in EKEventStore.shared.events(matching: predicate) {
            let calendar = calendars.first { $0.ID == rawEvent.calendar.calendarIdentifier }!
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
                let email = rawAttendee.safeNSURL?.resourceSpecifier
                let attendee = MBEventAttendee(email: email, name: rawAttendee.name, status: attendeeStatus, optional: optional, isCurrentUser: rawAttendee.isCurrentUser)

                attendees.append(attendee)
            }

            let event = MBEvent(
                id: rawEvent.calendarItemIdentifier,
                lastModifiedDate: rawEvent.lastModifiedDate,
                title: rawEvent.title,
                status: status,
                notes: rawEvent.notes,
                location: rawEvent.location,
                url: rawEvent.url,
                organizer: organizer,
                attendees: attendees,
                startDate: rawEvent.startDate,
                endDate: rawEvent.endDate,
                isAllDay: rawEvent.isAllDay,
                recurrent: rawEvent.hasRecurrenceRules,
                calendar: calendar
            )
            events.append(event)
        }
        return events
    }
}

func getGmailAccount(_ text: String) -> String? {
    // Hacky and likely to break, but should work until Apple changes something
    let regex = try! NSRegularExpression(pattern: #""mailto:(.+@.+)""#)
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range(at: 1), in: text)!]) }
    if !resultsMap.isEmpty {
        return resultsMap.first
    }
    return nil
}
