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

        var futureEvents = events.filter { $0.endDate > startPeriod && $0.startDate < endPeriod }

        if !settings.includesPersonalEvents {
            futureEvents = futureEvents.filter(\.hasAttendees)
        }

        // The selection loop terminates on the first candidate beyond the
        // 10-minute window and hands off from a running event to the next one,
        // both of which assume ascending start order. `CalendarSync` sorts in
        // production, but the policy must not depend on the caller doing so.
        futureEvents.sort { $0.startDate < $1.startDate }

        var result: EventSelectionEvent?

        for event in futureEvents {
            let dismissal = EventSelectionDismissal(
                id: event.id,
                lastModifiedDate: event.lastModifiedDate
            )
            if settings.dismissedEvents.contains(dismissal) {
                continue
            }

            if event.isAllDay {
                continue
            }

            if !event.hasMeetingLink, linkRequired || settings.requiresMeetingLinkForNonAllDayEvents {
                continue
            }

            if event.participationStatus == .declined {
                continue
            }

            if event.participationStatus == .pending, settings.hidesPendingEvents {
                continue
            }

            if event.participationStatus == .tentative, settings.hidesTentativeEvents {
                continue
            }

            if event.status == .canceled {
                continue
            }

            if event.startDate < now, settings.ongoingEventVisibility == .hideImmediateAfter {
                continue
            }

            if now >= event.startDate.addingTimeInterval(600), settings.ongoingEventVisibility == .showTenMinAfter {
                continue
            }

            if result == nil {
                result = event
                continue
            } else {
                // `.showTenMinBeforeNext` means "keep the running event until a
                // nearer event enters the 10-minute window". That hand-off only
                // makes sense while the held result is still an ongoing event;
                // once the soonest upcoming event has been selected there is no
                // running event left to defer, so stop and return it. Without
                // this guard the loop keeps advancing to every later event that
                // also starts within the window and the soonest one is skipped.
                let heldResultIsOngoing = result!.startDate <= now
                if heldResultIsOngoing,
                   event.startDate < now.addingTimeInterval(600),
                   settings.ongoingEventVisibility == .showTenMinBeforeNext {
                    result = event
                } else {
                    break
                }
            }
        }
        return result
    }
}
