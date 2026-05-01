//
//  StatusBarIconPolicy+MeetingBar.swift
//  MeetingBar
//

import Foundation

extension StatusBarIconFormat {
    /// Maps the production `EventTitleIconFormat` (defined in
    /// `Utilities/Constants.swift`, used as a Defaults type) to the hostless
    /// shadow enum the policy operates on.
    init(_ format: EventTitleIconFormat) {
        switch format {
        case .calendar: self = .calendar
        case .appicon: self = .appicon
        case .eventtype: self = .eventtype
        case .none: self = .none
        }
    }
}

extension StatusBarIconAssets {
    /// Asset names taken from `MenuStyleConstants` so production code stays
    /// the single source of truth.
    static var production: StatusBarIconAssets {
        StatusBarIconAssets(
            appIcon: MenuStyleConstants.appIconName,
            calendarCheckmark: MenuStyleConstants.calendarCheckmarkIconName,
            calendar: MenuStyleConstants.calendarIconName
        )
    }
}
