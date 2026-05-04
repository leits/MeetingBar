//
//  StatusBarMenuState.swift
//  MeetingBar
//

import Foundation

/// A value-typed snapshot of everything the status bar menu needs to render
/// without reading `Defaults` or reaching through singletons.
///
/// Built by `StatusBarMenuStateFactory.make(from:)` and consumed by
/// `MenuBuilder`.  Must not import AppKit or UserNotifications.
struct StatusBarMenuState: Equatable {
    // MARK: - Events (split by day)

    var todayEvents: [MBEvent] = []
    var tomorrowEvents: [MBEvent] = []
    var nextEvent: MBEvent?

    // MARK: - Structural switches

    /// Whether any calendars are selected (drives the "no calendars" empty state).
    var hasSelectedCalendars: Bool = false

    /// Which period to show in the menu.
    var showEventsForPeriod: ShowEventsForPeriod = .today

    /// Whether the day-timeline bar should appear above the event list.
    var showTimeline: Bool = false

    /// Whether meeting titles are hidden in the status bar title and menu.
    var hideMeetingTitle: Bool = false

    // MARK: - Bookmarks

    var bookmarks: [Bookmark] = []
}
