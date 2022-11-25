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
    var safeNSURL: NSURL? {
        perform(#selector(getter: EKParticipant.url))?.takeUnretainedValue() as? NSURL
    }
}

extension EKEventStore: EventStore {
    static var shared = EKEventStore()

    func signIn() -> Promise<Void> {
        Promise { seal in
            EKEventStore.shared.requestAccess(to: .event) { granted, _ in
                if granted {
                    var sources = EKEventStore.shared.sources
                    sources.append(contentsOf: EKEventStore.shared.delegateSources)

                    EKEventStore.shared = EKEventStore(sources: sources)
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
            
            for ekcalendar in EKEventStore.shared.calendars(for: .event) {
                let dateFrom = Calendar.current.startOfDay(for: Date())
                let dateTo = Calendar.current.date(byAdding: .day, value: 1, to: dateFrom)!
                
                let predicate = predicateForEvents(withStart: dateFrom, end: dateTo, calendars: [ekcalendar])
                let email = EKEventStore.shared.events(matching: predicate).first?.attendees?.first { $0.isCurrentUser }?.safeNSURL?.resourceSpecifier
                
                let calendar = MBCalendar(
                    title: ekcalendar.title,
                    ID: ekcalendar.calendarIdentifier,
                    source: ekcalendar.source.title,
                    email: getGmailAccount(ekcalendar.source.description) ?? email,
                    color: ekcalendar.color
                )
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
                    ID: rawEvent.calendarItemIdentifier,
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
            seal.fulfill(events)
        }
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
