//
//  AppState.swift
//  MeetingBar
//

import Foundation

/// The complete observable state of the application at a point in time.
///
/// `AppState` is value-typed and derived from lower-level sources of truth
/// (`EventManager`, `SettingsStore`, system state).  Renderers (status bar,
/// menus, notifications) should read from `AppState` rather than reaching
/// through managers directly.
struct AppState: Equatable {
    // MARK: - Calendar

    var calendars: [MBCalendar] = []
    var events: [MBEvent] = []
    var activeProvider: EventStoreProvider = .macOSEventKit

    // MARK: - System

    /// `true` while the screen is locked or the display is off.
    var screenIsLocked: Bool = false

    // MARK: - Derived

    /// Next upcoming event that has not been dismissed and is not all-day.
    var nextEvent: MBEvent? {
        events.first { !$0.isAllDay && $0.endDate > Date() }
    }
}
