//
//  EventFiltering+MeetingBar.swift
//  MeetingBar
//

import Defaults
import Foundation

extension EventFilterSettings {
    static var current: EventFilterSettings {
        EventFilterSettings(
            filterEventRegexes: Defaults[.filterEventRegexes],
            allDayEvents: EventFilterAllDayMode(Defaults[.allDayEvents]),
            nonAllDayEvents: EventFilterNonAllDayMode(Defaults[.nonAllDayEvents]),
            hidesPendingEvents: Defaults[.showPendingEvents] == .hide,
            hidesTentativeEvents: Defaults[.showTentativeEvents] == .hide,
            hidesDeclinedEvents: Defaults[.declinedEventsAppereance] == .hide
        )
    }
}

extension EventFilterEvent {
    init(event: MBEvent, sourceIndex: Int) {
        self.init(
            sourceIndex: sourceIndex,
            id: event.id,
            title: event.title,
            isAllDay: event.isAllDay,
            hasMeetingLink: event.meetingLink?.url != nil,
            participationStatus: EventFilterEvent.ParticipationStatus(event.participationStatus)
        )
    }
}

private extension EventFilterAllDayMode {
    init(_ mode: AlldayEventsAppereance) {
        switch mode {
        case .show:
            self = .show
        case .show_with_meeting_link_only:
            self = .showWithMeetingLinkOnly
        case .hide:
            self = .hide
        }
    }
}

private extension EventFilterNonAllDayMode {
    init(_ mode: NonAlldayEventsAppereance) {
        switch mode {
        case .show, .show_inactive_without_meeting_link:
            self = .show
        case .hide_without_meeting_link:
            self = .hideWithoutMeetingLink
        }
    }
}

private extension EventFilterEvent.ParticipationStatus {
    init(_ status: MBEventAttendeeStatus) {
        switch status {
        case .pending:
            self = .pending
        case .tentative:
            self = .tentative
        case .declined:
            self = .declined
        case .unknown, .accepted, .delegated, .completed, .inProcess:
            self = .active
        }
    }
}
