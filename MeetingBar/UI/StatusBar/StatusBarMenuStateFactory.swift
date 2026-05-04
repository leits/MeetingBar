//
//  StatusBarMenuStateFactory.swift
//  MeetingBar
//

import Defaults
import Foundation

/// Builds a `StatusBarMenuState` snapshot from the current event list and
/// `Defaults` settings.  Lives in the UI layer so it may read `Defaults`;
/// `StatusBarMenuState` itself stays clean.
@MainActor
enum StatusBarMenuStateFactory {
    static func make(from events: [MBEvent]) -> StatusBarMenuState {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let todayEvents = events.filter {
            Calendar.current.isDate($0.startDate, inSameDayAs: today)
        }
        let tomorrowEvents = events.filter {
            Calendar.current.isDate($0.startDate, inSameDayAs: tomorrow)
        }

        return StatusBarMenuState(
            todayEvents: todayEvents,
            tomorrowEvents: tomorrowEvents,
            nextEvent: events.nextEvent(),
            hasSelectedCalendars: !Defaults[.selectedCalendarIDs].isEmpty,
            showEventsForPeriod: Defaults[.showEventsForPeriod],
            showTimeline: Defaults[.showTimelineInMenu],
            hideMeetingTitle: Defaults[.hideMeetingTitle],
            bookmarks: Defaults[.bookmarks]
        )
    }
}
