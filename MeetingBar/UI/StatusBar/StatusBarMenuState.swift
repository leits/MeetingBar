//
//  StatusBarMenuState.swift
//  MeetingBar
//

import Defaults
import Foundation

/// Value-typed snapshot of everything the status bar menu needs to render
/// without reading `Defaults` or reaching through singletons.
///
/// Built by `StatusBarMenuState.make(...)` and consumed by `MenuBuilder`.
/// Must not import AppKit or UserNotifications.
struct StatusBarMenuState: Equatable {
    // MARK: - Events (split by day)

    var todayEvents: [MBEvent] = []
    var tomorrowEvents: [MBEvent] = []
    var nextEvent: MBEvent?

    // MARK: - Settings snapshot

    /// Full settings snapshot. `MenuBuilder` reads display/filter settings from
    /// here instead of touching `Defaults` directly.
    var settings: AppSettings = .empty

    // MARK: - Pre-computed display flags

    /// Whether any calendars are selected (drives the "no calendars" empty state).
    var hasSelectedCalendars: Bool = false

    /// Whether more than one calendar is selected (controls calendar-name display
    /// in event details).
    var hasMultipleSelectedCalendars: Bool = false

    /// Whether the day-timeline bar should appear above the event list.
    var showTimeline: Bool = false

    /// Time-format display (military vs am/pm) used when formatting event times.
    var timeFormat: TimeFormat = .military

    // MARK: - Changelog / install state

    /// Major-version prefix of the running app (e.g. "5.0").
    var appMajorVersion: String = ""

    /// Major-version prefix of the last release the user has acknowledged in
    /// the changelog. When this differs from `appMajorVersion`, the menu shows
    /// an unread-changelog hint.
    var lastRevisedMajorVersion: String = ""

    /// Whether the app was installed from the Mac App Store. Hides certain
    /// release-channel UI when true.
    var isInstalledFromAppStore: Bool = false

    // MARK: - Convenience accessors

    /// Settings groups exposed for shorter call sites in MenuBuilder.
    var events: EventDisplaySettings { settings.events }
    var statusBar: StatusBarSettings { settings.statusBar }
    var menu: MenuSettings { settings.menu }
    var meetings: MeetingSettings { settings.meetings }
}

// MARK: - Factory

@MainActor
extension StatusBarMenuState {
    /// Builds a `StatusBarMenuState` snapshot from the current event list
    /// plus the current settings/Defaults boundary. The factory is the only
    /// place inside `StatusBarMenuState` that reads `Defaults` — the value
    /// type itself stays clean.
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
