//
//  EventFilterPolicy.swift
//  MeetingBar
//

import Foundation

enum EventFilterAllDayMode {
    case show
    case showWithMeetingLinkOnly
    case hide
}

enum EventFilterNonAllDayMode {
    case show
    case hideWithoutMeetingLink
}

struct EventFilterSettings {
    let filterEventRegexes: [String]
    let allDayEvents: EventFilterAllDayMode
    let nonAllDayEvents: EventFilterNonAllDayMode
    let hidesPendingEvents: Bool
    let hidesTentativeEvents: Bool
    let hidesDeclinedEvents: Bool
}

struct EventFilterEvent: Equatable {
    enum ParticipationStatus {
        case active
        case pending
        case tentative
        case declined
    }

    let sourceIndex: Int
    let id: String
    let title: String
    let isAllDay: Bool
    let hasMeetingLink: Bool
    let participationStatus: ParticipationStatus
}

enum EventFilterPolicy {
    static func filter(_ events: [EventFilterEvent], settings: EventFilterSettings) -> [EventFilterEvent] {
        var result: [EventFilterEvent] = []
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
                case .showWithMeetingLinkOnly:
                    if !event.hasMeetingLink {
                        continue
                    }
                case .hide:
                    continue
                }
            } else {
                switch settings.nonAllDayEvents {
                case .show:
                    break
                case .hideWithoutMeetingLink:
                    if !event.hasMeetingLink {
                        continue
                    }
                }
            }

            if settings.hidesPendingEvents, event.participationStatus == .pending {
                continue
            }

            if settings.hidesTentativeEvents, event.participationStatus == .tentative {
                continue
            }

            if settings.hidesDeclinedEvents, event.participationStatus == .declined {
                continue
            }

            result.append(event)
        }
        return result
    }
}
