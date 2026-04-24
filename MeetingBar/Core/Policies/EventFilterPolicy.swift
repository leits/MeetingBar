//
//  EventFilterPolicy.swift
//  MeetingBar
//

import Defaults
import Foundation

struct EventFilterSettings {
    let filterEventRegexes: [String]
    let allDayEvents: AlldayEventsAppereance
    let nonAllDayEvents: NonAlldayEventsAppereance
    let showPendingEvents: PendingEventsAppereance
    let showTentativeEvents: TentativeEventsAppereance
    let declinedEventsAppereance: DeclinedEventsAppereance

    static var current: EventFilterSettings {
        EventFilterSettings(
            filterEventRegexes: Defaults[.filterEventRegexes],
            allDayEvents: Defaults[.allDayEvents],
            nonAllDayEvents: Defaults[.nonAllDayEvents],
            showPendingEvents: Defaults[.showPendingEvents],
            showTentativeEvents: Defaults[.showTentativeEvents],
            declinedEventsAppereance: Defaults[.declinedEventsAppereance]
        )
    }
}

enum EventFilterPolicy {
    static func filter(_ events: [MBEvent], settings: EventFilterSettings) -> [MBEvent] {
        var result: [MBEvent] = []
        outerloop: for event in events {
            for pattern in settings.filterEventRegexes {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let hasMatch = regex.firstMatch(in: event.title, range: NSRange(event.title.startIndex..., in: event.title)) != nil
                    if hasMatch {
                        continue outerloop
                    }
                }
            }

            if event.isAllDay {
                switch settings.allDayEvents {
                case .show:
                    break
                case .show_with_meeting_link_only:
                    if event.meetingLink?.url == nil {
                        continue
                    }
                case .hide:
                    continue
                }
            } else {
                switch settings.nonAllDayEvents {
                case .show, .show_inactive_without_meeting_link:
                    break
                case .hide_without_meeting_link:
                    if event.meetingLink?.url == nil {
                        continue
                    }
                }
            }

            switch settings.showPendingEvents {
            case .show, .show_inactive, .show_underlined:
                break
            case .hide:
                if event.participationStatus == .pending {
                    continue
                }
            }

            switch settings.showTentativeEvents {
            case .show, .show_inactive, .show_underlined:
                break
            case .hide:
                if event.participationStatus == .tentative {
                    continue
                }
            }

            switch settings.declinedEventsAppereance {
            case .show_inactive, .strikethrough:
                break
            case .hide:
                if event.participationStatus == .declined {
                    continue
                }
            }

            result.append(event)
        }
        return result
    }
}
