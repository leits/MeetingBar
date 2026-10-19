//
//  EventSelectionPolicy.swift
//  MeetingBar
//

import Foundation

enum EventSelectionPeriod {
    case today
    case todayAndTomorrow
}

enum EventSelectionOngoingVisibility {
    case hideImmediateAfter
    case showTenMinAfter
    case showTenMinBeforeNext
}

struct EventSelectionSettings {
    let period: EventSelectionPeriod
    let includesPersonalEvents: Bool
    let dismissedEvents: Set<EventSelectionDismissal>
    let requiresMeetingLinkForNonAllDayEvents: Bool
    let hidesPendingEvents: Bool
    let hidesTentativeEvents: Bool
    let ongoingEventVisibility: EventSelectionOngoingVisibility
}

struct EventSelectionDismissal: Hashable {
    let id: String
    let lastModifiedDate: Date?
}

struct EventSelectionEvent: Equatable {
    enum Status {
        case active
        case canceled
    }

    enum ParticipationStatus {
        case active
        case pending
        case tentative
        case declined
    }

    let sourceIndex: Int
    let id: String
    let lastModifiedDate: Date?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let hasMeetingLink: Bool
    let hasAttendees: Bool
    let status: Status
    let participationStatus: ParticipationStatus
}

enum EventSelection {
    static func nextEvent(
        from events: [EventSelectionEvent],
        linkRequired: Bool,
        settings: EventSelectionSettings,
        now: Date
    ) -> EventSelectionEvent? {
        let startPeriod = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
        let todayMidnight = Calendar.current.startOfDay(for: now)
        let endPeriod: Date
        switch settings.period {
        case .today:
            endPeriod = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!
        case .todayAndTomorrow:
            endPeriod = Calendar.current.date(byAdding: .day, value: 2, to: todayMidnight)!
        }

        // Provider results need not arrive chronologically. Ties keep the
        // original source order for a deterministic next-meeting choice.
        var futureEvents = events.filter { $0.endDate > startPeriod && $0.startDate < endPeriod }
        futureEvents.sort {
            if $0.startDate == $1.startDate { return $0.sourceIndex < $1.sourceIndex }
            return $0.startDate < $1.startDate
        }

        var result: EventSelectionEvent?

        for event in futureEvents {
            if isExcluded(event, linkRequired: linkRequired, settings: settings) {
                continue
            }

            if event.startDate < now, settings.ongoingEventVisibility == .hideImmediateAfter {
                continue
            }

            if now >= event.startDate.addingTimeInterval(600), settings.ongoingEventVisibility == .showTenMinAfter {
                continue
            }

            guard let selected = result else {
                result = event
                continue
            }

            // An ongoing meeting hands off to the next meeting only when
            // that meeting begins within ten minutes. A future selection
            // must never be replaced by a later future meeting.
            if settings.ongoingEventVisibility == .showTenMinBeforeNext,
               selected.startDate <= now,
               event.startDate < now.addingTimeInterval(600) {
                result = event
            } else {
                break
            }
        }
        return result
    }

    /// Other meetings running at the same time as `primary`: any event whose
    /// time range intersects it and that the menu would show (not dismissed,
    /// declined, canceled, all-day, or hidden by settings). Keeps input order,
    /// which `CalendarSync` already sorts by start. An all-day `primary` has
    /// no meaningful "same time", so it lists nothing.
    static func overlappingEvents(
        with primary: EventSelectionEvent,
        from events: [EventSelectionEvent],
        settings: EventSelectionSettings
    ) -> [EventSelectionEvent] {
        guard !primary.isAllDay else { return [] }
        return events.filter {
            $0.id != primary.id
                && $0.startDate < primary.endDate
                && $0.endDate > primary.startDate
                && !isExcluded($0, linkRequired: false, settings: settings)
        }
    }

    private static func isExcluded(
        _ event: EventSelectionEvent,
        linkRequired: Bool,
        settings: EventSelectionSettings
    ) -> Bool {
        let dismissal = EventSelectionDismissal(id: event.id, lastModifiedDate: event.lastModifiedDate)
        if settings.dismissedEvents.contains(dismissal) { return true }
        if !settings.includesPersonalEvents, !event.hasAttendees { return true }
        if event.isAllDay { return true }
        if !event.hasMeetingLink, linkRequired || settings.requiresMeetingLinkForNonAllDayEvents { return true }
        if event.participationStatus == .declined { return true }
        if event.participationStatus == .pending, settings.hidesPendingEvents { return true }
        if event.participationStatus == .tentative, settings.hidesTentativeEvents { return true }
        return event.status == .canceled
    }
}
