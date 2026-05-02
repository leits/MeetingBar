//
//  StatusBarPresentationPolicy+MeetingBar.swift
//  MeetingBar
//

import Defaults
import Foundation

extension StatusBarPresentationSettings {
    /// Snapshot of the relevant `Defaults` keys the policy reads. The
    /// renderer (`StatusBarItemController.updateTitle`) builds this on every
    /// title update and passes it to `StatusBarPresentationPolicy.mode`.
    static var current: StatusBarPresentationSettings {
        StatusBarPresentationSettings(
            hasSelectedCalendars: !Defaults[.selectedCalendarIDs].isEmpty,
            showEventMaxTimeUntilEventEnabled: Defaults[.showEventMaxTimeUntilEventEnabled],
            showEventMaxTimeUntilEventThreshold: Defaults[.showEventMaxTimeUntilEventThreshold]
        )
    }
}

extension StatusBarTimeDisplay {
    init(_ format: EventTimeFormat) {
        switch format {
        case .show:
            self = .show
        case .show_under_title:
            self = .showUnderTitle
        case .hide:
            self = .hide
        }
    }
}

extension StatusBarEventParticipation {
    init(_ status: MBEventAttendeeStatus) {
        switch status {
        case .pending:
            self = .pending
        case .tentative:
            self = .tentative
        default:
            self = .normal
        }
    }
}

extension StatusBarParticipationDisplay {
    init(_ pendingAppearance: PendingEventsAppereance) {
        switch pendingAppearance {
        case .show_inactive:
            self = .inactive
        case .show_underlined:
            self = .underlined
        case .show, .hide:
            self = .normal
        }
    }

    init(_ tentativeAppearance: TentativeEventsAppereance) {
        switch tentativeAppearance {
        case .show_inactive:
            self = .inactive
        case .show_underlined:
            self = .underlined
        case .show, .hide:
            self = .normal
        }
    }
}

extension StatusBarEventPresentationInput {
    init(_ event: MBEvent) {
        self.init(
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            meetingService: event.meetingLink?.service,
            participation: StatusBarEventParticipation(event.participationStatus)
        )
    }
}

extension StatusBarPresenterSettings {
    static var current: StatusBarPresenterSettings {
        StatusBarPresenterSettings(
            presentation: .current,
            title: .current,
            timeDisplay: StatusBarTimeDisplay(Defaults[.eventTimeFormat]),
            iconFormat: StatusBarIconFormat(Defaults[.eventTitleIconFormat]),
            iconFormatAssetName: Defaults[.eventTitleIconFormat].rawValue,
            iconAssets: .production,
            pendingDisplay: StatusBarParticipationDisplay(Defaults[.showPendingEvents]),
            tentativeDisplay: StatusBarParticipationDisplay(Defaults[.showTentativeEvents]),
            compactTitleLimit: 28
        )
    }
}
