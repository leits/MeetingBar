//
//  StatusBarTitlePolicy+MeetingBar.swift
//  MeetingBar
//

import Defaults
import Foundation

extension StatusBarEventTitleFormat {
    init(_ format: EventTitleFormat) {
        switch format {
        case .show: self = .show
        case .dot: self = .dot
        case .none: self = .none
        }
    }
}

extension StatusBarTitleLabels {
    static var current: StatusBarTitleLabels {
        StatusBarTitleLabels(
            genericMeetingTitle: "general_meeting".loco(),
            noTitle: "status_bar_no_title".loco(),
            activeEventTimeFormat: "status_bar_event_status_now".loco(),
            upcomingEventTimeFormat: "status_bar_event_status_in".loco()
        )
    }
}

extension StatusBarTitleSettings {
    static var current: StatusBarTitleSettings {
        StatusBarTitleSettings(
            titleFormat: StatusBarEventTitleFormat(Defaults[.eventTitleFormat]),
            hideMeetingTitle: Defaults[.hideMeetingTitle],
            titleLength: Defaults[.statusbarEventTitleLength],
            labels: .current
        )
    }
}
