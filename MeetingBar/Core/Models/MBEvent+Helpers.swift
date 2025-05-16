//
//  MBEvent+Helpers.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Defaults
import Foundation

public extension Array where Element == MBEvent {
    /// Returns only those events that pass all the user’s Defaults filters.

    func filtered() -> [MBEvent] {
        var result: [MBEvent] = []
        outerloop: for event in self {
            // Filter events base on custom user regexes
            for pattern in Defaults[.filterEventRegexes] {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let hasMatch = regex.firstMatch(in: event.title, range: NSRange(event.title.startIndex..., in: event.title)) != nil
                    if hasMatch {
                        continue outerloop
                    }
                }
            }

            if event.isAllDay {
                // Filter all day events
                switch Defaults[.allDayEvents] {
                case .show:
                    break
                case .show_with_meeting_link_only:
                    if event.meetingLink?.url == nil {
                        continue // Skip this event
                    }
                case .hide:
                    continue // Skip this event
                }
            } else {
                // Filter not for all day events
                switch Defaults[.nonAllDayEvents] {
                case .show, .show_inactive_without_meeting_link:
                    break
                case .hide_without_meeting_link:
                    if event.meetingLink?.url == nil {
                        continue // Skip this event
                    }
                }
            }

            // Filter pending events
            switch Defaults[.showPendingEvents] {
            case .show, .show_inactive, .show_underlined:
                break
            case .hide:
                if event.participationStatus == .pending {
                    continue // Skip this event
                }
            }

            // Filter tentative events
            switch Defaults[.showTentativeEvents] {
            case .show, .show_inactive, .show_underlined:
                break
            case .hide:
                if event.participationStatus == .tentative {
                    continue // Skip this event
                }
            }

            // Filter declined events
            switch Defaults[.declinedEventsAppereance] {
            case .show_inactive, .strikethrough:
                break
            case .hide:
                if event.participationStatus == .declined {
                    continue // Skip this event
                }
            }

            result.append(event)
        }
        return result
    }

    /// From a pre-filtered, sorted array, find the nearest upcoming MBEvent.
    func nextEvent(linkRequired: Bool = false) -> MBEvent? {
        var nextEvent: MBEvent?

        let now = Date()
        let startPeriod = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
        var endPeriod: Date

        let todayMidnight = Calendar.current.startOfDay(for: now)
        switch Defaults[.showEventsForPeriod] {
        case .today:
            endPeriod = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!
        case .today_n_tomorrow:
            endPeriod = Calendar.current.date(byAdding: .day, value: 2, to: todayMidnight)!
        }

        // Filter out passed or not started events
        var futureEvents = filter { $0.endDate > startPeriod && $0.startDate < endPeriod }

        // Filter out personal events, if not marked as 'active'
        if Defaults[.personalEventsAppereance] != .show_active {
            futureEvents = futureEvents.filter { !$0.attendees.isEmpty }
        }

        for event in futureEvents {
            // Skip event if dismissed
            if Defaults[.dismissedEvents].contains(where: { $0.id == event.id }) {
                continue
            }

            // Skip event if allday
            if event.isAllDay {
                continue
            }

            // Skip event if events without links should be skipped
            let nonAllDaysEventOnlyWithLink = (Defaults[.nonAllDayEvents] == .show_inactive_without_meeting_link || Defaults[.nonAllDayEvents] == .hide_without_meeting_link)
            if event.meetingLink == nil, linkRequired || nonAllDaysEventOnlyWithLink {
                continue
            }

            // Skip event if declined
            if event.participationStatus == .declined {
                continue
            }

            // Skip event if pending events should be skipped
            if event.participationStatus == .pending, Defaults[.showPendingEvents] == .hide || Defaults[.showPendingEvents] == .show_inactive {
                continue
            }

            // Skip event if pending events should be skipped
            if event.participationStatus == .tentative, Defaults[.showTentativeEvents] == .hide || Defaults[.showTentativeEvents] == .show_inactive {
                continue
            }

            // Skip event if canceled
            if event.status == .canceled {
                continue
            }

            // Skip event if past events should be skipped
            if event.startDate < now, Defaults[.ongoingEventVisibility] == .hideImmediateAfter {
                continue
            }

            // Skip event if past events should be skipped after 10 min
            if event.startDate < now.addingTimeInterval(600), Defaults[.ongoingEventVisibility] == .showTenMinAfter {
                continue
            }

            // If the current event is still going on,
            // but the next event is closer than 10 minutes later and settings are set to switch
            // then show the next event
            if nextEvent == nil {
                // Save our next event candidate and continue to look for the second one
                nextEvent = event
                continue
            } else {
                if event.startDate < now.addingTimeInterval(600), Defaults[.ongoingEventVisibility] == .showTenMinBeforeNext {
                    nextEvent = event
                } else {
                    break
                }
            }
        }
        return nextEvent
    }
}
