//
//  AppEnvironment.swift
//  MeetingBar
//

import Foundation

/// Injectable side-effect clients used by `AppModel`.
///
/// Production code injects the real implementations; tests inject fakes.
/// `AppEnvironment` must not import AppKit, EventKit, UserNotifications, or
/// AppAuth so that `AppModel` remains hostless-testable.
struct AppEnvironment {
    /// Fetch current calendars and events.
    var refreshCalendars: @MainActor () async -> ([MBCalendar], EventStoreProvider)
    var refreshEvents: @MainActor ([MBCalendar]) async -> [MBEvent]

    /// Reconcile system notification requests with the current plan.
    var reconcileNotifications: @MainActor ([MBEvent]) async -> Void

    /// Current wall-clock time (injectable for tests).
    var now: @Sendable () -> Date

    // MARK: - Production default

    @MainActor
    static func live(
        eventManager: EventManager,
        notificationScheduler: NotificationScheduler
    ) -> AppEnvironment {
        AppEnvironment(
            refreshCalendars: {
                (eventManager.calendars, eventManager.repository.activeProviderName)
            },
            refreshEvents: { _ in
                eventManager.events
            },
            reconcileNotifications: { events in
                await notificationScheduler.reconcile(
                    events: events,
                    settings: .currentForScheduler
                )
            },
            now: { Date() }
        )
    }
}
