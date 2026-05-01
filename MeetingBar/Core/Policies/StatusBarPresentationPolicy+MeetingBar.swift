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
