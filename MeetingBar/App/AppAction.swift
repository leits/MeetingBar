//
//  AppAction.swift
//  MeetingBar
//

import Foundation

/// All events that change application state.
///
/// `AppAction`s are dispatched to `AppModel.send(_:)` and never carry
/// AppKit/UserNotifications/EventKit types so the model stays testable without
/// a running host app.
enum AppAction {
    // MARK: - Lifecycle

    case launched
    case willTerminate

    // MARK: - System events

    case screenLocked
    case screenUnlocked
    case didWake
    case timezoneChanged
    case dayChanged

    // MARK: - Calendar

    case calendarStoreChanged
    case refreshCalendars
    case calendarsLoaded([MBCalendar], provider: EventStoreProvider)
    case eventsLoaded([MBEvent])
    case calendarRefreshFailed(Error)
    case providerChanged(EventStoreProvider)

    // MARK: - Settings

    case settingsChanged

    // MARK: - Provider

    /// Switch the active calendar provider.  `signOut = true` drops the current OAuth session first.
    case changeProvider(EventStoreProvider, signOut: Bool)

    // MARK: - Notification responses

    case joinMeeting(eventID: String)
    case dismissMeeting(eventID: String)
    case snoozeMeeting(eventID: String, action: NotificationEventTimeAction)

    // MARK: - Notification reconcile

    case reconcileNotifications
}
