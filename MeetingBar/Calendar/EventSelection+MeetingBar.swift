//
//  EventSelection+MeetingBar.swift
//  MeetingBar
//

import Foundation

extension EventSelectionSettings {
    @MainActor
    static var current: EventSelectionSettings {
        EventSelectionSettings(AppSettings.current.events)
    }

    init(_ settings: EventDisplaySettings) {
        self.init(
            period: EventSelectionPeriod(settings.showEventsForPeriod),
            includesPersonalEvents: settings.personalEventsAppearance == .show_active,
            dismissedEvents: Set(settings.dismissedEvents.map {
                EventSelectionDismissal(id: $0.id, lastModifiedDate: $0.lastModifiedDate)
            }),
            requiresMeetingLinkForNonAllDayEvents: settings.nonAllDayEvents.requiresMeetingLink,
            hidesPendingEvents: settings.showPendingEvents.hidesFromNextEvent,
            hidesTentativeEvents: settings.showTentativeEvents.hidesFromNextEvent,
            ongoingEventVisibility: EventSelectionOngoingVisibility(settings.ongoingEventVisibility)
        )
    }
}

extension EventSelectionEvent {
    init(event: MBEvent, sourceIndex: Int) {
        self.init(
            sourceIndex: sourceIndex,
            id: event.id,
            lastModifiedDate: event.lastModifiedDate,
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
