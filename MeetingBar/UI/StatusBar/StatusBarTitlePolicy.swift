//
//  StatusBarTitlePolicy.swift
//  MeetingBar
//

import Foundation

enum StatusBarEventTitleFormat: Equatable {
    case show
    case dot
    case none
}

struct StatusBarTitleLabels: Equatable {
    let genericMeetingTitle: String
    let noTitle: String
    let activeEventTimeFormat: String
    let upcomingEventTimeFormat: String
}

struct StatusBarTitleSettings: Equatable {
    let titleFormat: StatusBarEventTitleFormat
    let hideMeetingTitle: Bool
    let titleLength: Int
    let labels: StatusBarTitleLabels
}

struct StatusBarTitleText: Equatable {
    let title: String
    let time: String
    let isActiveEvent: Bool
}

enum StatusBarTitlePolicy {
    static func text(
        eventTitle rawTitle: String?,
        startDate: Date,
        endDate: Date,
        settings: StatusBarTitleSettings,
        now: Date,
        calendar: Calendar
    ) -> StatusBarTitleText {
        let title = formattedTitle(rawTitle, settings: settings)
        let isActiveEvent = startDate <= now && endDate > now
        let eventDate = isActiveEvent ? endDate : startDate
        let timeLeft = formattedTimeLeft(from: now.addingTimeInterval(-60), to: eventDate, calendar: calendar)
        let timeFormat = isActiveEvent ? settings.labels.activeEventTimeFormat : settings.labels.upcomingEventTimeFormat
        let time = String(format: timeFormat, timeLeft)
        return StatusBarTitleText(title: title, time: time, isActiveEvent: isActiveEvent)
    }

    static func shortenTitle(_ rawTitle: String?, limit: Int, noTitle: String) -> String {
        var eventTitle = String(rawTitle ?? noTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0 else { return "..." }
        if eventTitle.count > limit {
            let index = eventTitle.index(eventTitle.startIndex, offsetBy: limit - 1)
            eventTitle = String(eventTitle[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
            eventTitle += "..."
        }
        return eventTitle
    }

    private static func formattedTitle(_ rawTitle: String?, settings: StatusBarTitleSettings) -> String {
        switch settings.titleFormat {
        case .show:
            if settings.hideMeetingTitle {
                return settings.labels.genericMeetingTitle
            }
            return shortenTitle(
                rawTitle,
                limit: settings.titleLength,
                noTitle: settings.labels.noTitle
            )
            .replacingOccurrences(of: "\n", with: " ")
        case .dot:
            return "•"
        case .none:
            return ""
        }
    }

    private static func formattedTimeLeft(from start: Date, to end: Date, calendar: Calendar) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .hour, .day]
        formatter.calendar = calendar
        return formatter.string(from: start, to: end) ?? ""
    }
}
