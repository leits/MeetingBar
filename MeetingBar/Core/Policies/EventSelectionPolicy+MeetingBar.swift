//
//  EventSelectionPolicy+MeetingBar.swift
//  MeetingBar
//

import Defaults
import Foundation

extension EventSelectionSettings {
    static var current: EventSelectionSettings {
        EventSelectionSettings(
            period: EventSelectionPeriod(Defaults[.showEventsForPeriod]),
            includesPersonalEvents: Defaults[.personalEventsAppereance] == .show_active,
            dismissedEventIDs: Set(Defaults[.dismissedEvents].map(\.id)),
            requiresMeetingLinkForNonAllDayEvents: Defaults[.nonAllDayEvents].requiresMeetingLink,
            hidesPendingEvents: Defaults[.showPendingEvents].hidesFromNextEvent,
            hidesTentativeEvents: Defaults[.showTentativeEvents].hidesFromNextEvent,
            ongoingEventVisibility: EventSelectionOngoingVisibility(Defaults[.ongoingEventVisibility])
        )
    }
}

extension EventSelectionEvent {
    init(event: MBEvent, sourceIndex: Int) {
        self.init(
            sourceIndex: sourceIndex,
            id: event.id,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            hasMeetingLink: event.meetingLink != nil,
            hasAttendees: !event.attendees.isEmpty,
            status: event.status == .canceled ? .canceled : .active,
            participationStatus: EventSelectionEvent.ParticipationStatus(event.participationStatus)
        )
    }
}

private extension EventSelectionPeriod {
    init(_ period: ShowEventsForPeriod) {
        switch period {
        case .today:
            self = .today
        case .today_n_tomorrow:
            self = .todayAndTomorrow
        }
    }
}

private extension EventSelectionOngoingVisibility {
    init(_ visibility: OngoingEventVisibility) {
        switch visibility {
        case .hideImmediateAfter:
            self = .hideImmediateAfter
        case .showTenMinAfter:
            self = .showTenMinAfter
        case .showTenMinBeforeNext:
            self = .showTenMinBeforeNext
        }
    }
}

private extension EventSelectionEvent.ParticipationStatus {
    init(_ status: MBEventAttendeeStatus) {
        switch status {
        case .declined:
            self = .declined
        case .pending:
            self = .pending
        case .tentative:
            self = .tentative
        case .unknown, .accepted, .delegated, .completed, .inProcess:
            self = .active
        }
    }
}

private extension NonAlldayEventsAppereance {
    var requiresMeetingLink: Bool {
        self == .show_inactive_without_meeting_link || self == .hide_without_meeting_link
    }
}

private extension PendingEventsAppereance {
    var hidesFromNextEvent: Bool {
        self == .hide || self == .show_inactive
    }
}

private extension TentativeEventsAppereance {
    var hidesFromNextEvent: Bool {
        self == .hide || self == .show_inactive
    }
}
