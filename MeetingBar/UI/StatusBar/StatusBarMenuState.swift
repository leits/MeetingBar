//
//  StatusBarMenuState.swift
//  MeetingBar
//

import Foundation

/// A value-typed snapshot of everything the status bar menu and title need
/// to render without reading `Defaults` or reaching through singletons.
///
/// This type is produced by `StatusBarMenuStateFactory.make(from:settings:)` and
/// consumed by `MenuBuilder`.  It must not import AppKit or UserNotifications.
struct StatusBarMenuState: Equatable {
    // MARK: - Events

    var todayEvents: [MBEvent] = []
    var tomorrowEvents: [MBEvent] = []
    var nextEvent: MBEvent?

    // MARK: - Presentation switches

    var showTimeline: Bool = false
    var hideMeetingTitle: Bool = false

    // MARK: - Title

    var titleText: String = ""
    var titleIconName: String = ""

    // MARK: - Bookmarks

    var bookmarks: [Bookmark] = []

    // MARK: - Derived convenience

    var hasTodayEvents: Bool { !todayEvents.isEmpty }
    var hasTomorrowEvents: Bool { !tomorrowEvents.isEmpty }
}
