//
//  StatusBarMenuStateFactory.swift
//  MeetingBar
//

import Defaults
import Foundation

/// Builds a `StatusBarMenuState` snapshot from the current event list and the
/// current settings.  Lives in the UI layer so it may read `Defaults`;
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

        let settings = AppSettings.current
        let selectedCount = settings.calendar.selectedCalendarIDs.count

        return StatusBarMenuState(
            todayEvents: todayEvents,
            tomorrowEvents: tomorrowEvents,
            nextEvent: events.nextEvent(),
            settings: settings,
            hasSelectedCalendars: selectedCount > 0,
            hasMultipleSelectedCalendars: selectedCount > 1,
            showTimeline: settings.menu.showTimelineInMenu,
            timeFormat: Defaults[.timeFormat],
            appMajorVersion: String(Defaults[.appVersion].dropLast(2)),
            lastRevisedMajorVersion: String(Defaults[.lastRevisedVersionInChangelog].dropLast(2)),
            isInstalledFromAppStore: Defaults[.isInstalledFromAppStore]
        )
    }
}
