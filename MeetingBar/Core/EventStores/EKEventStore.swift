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

extension EKEventStore: @unchecked @retroactive Sendable {}

extension EKEventStore: EventStore {
    nonisolated(unsafe) static var shared = EKEventStore()

    public func signIn(forcePrompt: Bool = false) async throws {
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

    public func signOut() async {}

    public func refreshSources() async {
        EKEventStore.shared.refreshSourcesIfNecessary()
    }

    public func fetchAllCalendars() async throws -> [MBCalendar] {
        var allCalendars: [MBCalendar] = []

        for calendar in EKEventStore.shared.calendars(for: .event) {
            let calendar = MBCalendar(
                title: calendar.title,
                id: calendar.calendarIdentifier,
                source: calendar.source.title,
                email: getGmailAccount(calendar.source.description),
                color: calendar.color
            )
            allCalendars.append(calendar)
        }
        return allCalendars
    }

    public func fetchEventsForDateRange(for calendars: [MBCalendar], from dateFrom: Date, to dateTo: Date) async throws -> [MBEvent] {
        let selectedCalendars = EKEventStore.shared.calendars(for: .event).filter { calendars.map(\.id).contains($0.calendarIdentifier) }

        if selectedCalendars.isEmpty {
            return []
        }

        let predicate = predicateForEvents(withStart: dateFrom, end: dateTo, calendars: selectedCalendars)

        var events: [MBEvent] = []
        for rawEvent in EKEventStore.shared.events(matching: predicate) {
            guard let calendar = calendars.first(where: { $0.id == rawEvent.calendar.calendarIdentifier }) else {
                NSLog("Skipping EventKit event from unknown calendar id \(rawEvent.calendar.calendarIdentifier)")
                continue
            }
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
    // Hacky and likely to break, but should work until Apple changes something.
    // Non-greedy quantifiers stop at the first closing quote, otherwise input
    // with multiple mailto: occurrences captures everything between the first
    // and last quote.
    guard let regex = try? NSRegularExpression(pattern: #""mailto:([^"@]+@[^"]+)""#) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          match.numberOfRanges > 1,
          let captureRange = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[captureRange])
}
