//
//  EventSelectionPolicy.swift
//  MeetingBar
//

import Defaults
import Foundation

struct EventSelectionSettings {
    let showEventsForPeriod: ShowEventsForPeriod
    let personalEventsAppereance: PastEventsAppereance
    let dismissedEvents: [ProcessedEvent]
    let nonAllDayEvents: NonAlldayEventsAppereance
    let showPendingEvents: PendingEventsAppereance
    let showTentativeEvents: TentativeEventsAppereance
    let ongoingEventVisibility: OngoingEventVisibility

    static var current: EventSelectionSettings {
        EventSelectionSettings(
            showEventsForPeriod: Defaults[.showEventsForPeriod],
            personalEventsAppereance: Defaults[.personalEventsAppereance],
            dismissedEvents: Defaults[.dismissedEvents],
            nonAllDayEvents: Defaults[.nonAllDayEvents],
            showPendingEvents: Defaults[.showPendingEvents],
            showTentativeEvents: Defaults[.showTentativeEvents],
            ongoingEventVisibility: Defaults[.ongoingEventVisibility]
        )
    }
}

enum EventSelectionPolicy {
    static func nextEvent(
        from events: [MBEvent],
        linkRequired: Bool,
        settings: EventSelectionSettings,
        now: Date
    ) -> MBEvent? {
        let startPeriod = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
        let todayMidnight = Calendar.current.startOfDay(for: now)
        let endPeriod: Date
        switch settings.showEventsForPeriod {
        case .today:
            endPeriod = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!
        case .today_n_tomorrow:
            endPeriod = Calendar.current.date(byAdding: .day, value: 2, to: todayMidnight)!
        }

        var futureEvents = events.filter { $0.endDate > startPeriod && $0.startDate < endPeriod }

        if settings.personalEventsAppereance != .show_active {
            futureEvents = futureEvents.filter { !$0.attendees.isEmpty }
        }

        var result: MBEvent?

        for event in futureEvents {
            if settings.dismissedEvents.contains(where: { $0.id == event.id }) {
                continue
            }

            if event.isAllDay {
                continue
            }

            let nonAllDayOnlyWithLink = (settings.nonAllDayEvents == .show_inactive_without_meeting_link || settings.nonAllDayEvents == .hide_without_meeting_link)
            if event.meetingLink == nil, linkRequired || nonAllDayOnlyWithLink {
                continue
            }

            if event.participationStatus == .declined {
                continue
            }

            if event.participationStatus == .pending, settings.showPendingEvents == .hide || settings.showPendingEvents == .show_inactive {
                continue
            }

            if event.participationStatus == .tentative, settings.showTentativeEvents == .hide || settings.showTentativeEvents == .show_inactive {
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
                if event.startDate < now.addingTimeInterval(600), settings.ongoingEventVisibility == .showTenMinBeforeNext {
                    result = event
                } else {
                    break
                }
            }
        }
        return result
    }
}
