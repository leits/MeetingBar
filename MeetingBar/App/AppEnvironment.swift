//
//  AppEnvironment.swift
//  MeetingBar
//

import Combine
import Foundation

/// Injectable side-effect clients used by `AppModel`.
///
/// Production code injects the real implementations; tests inject fakes.
/// `AppEnvironment` must not import AppKit, EventKit, UserNotifications, or
/// AppAuth so that `AppModel` remains hostless-testable.
struct AppEnvironment {
    // MARK: - Live streams

    /// Live stream of the current event list from the active provider.
    var eventsPublisher: AnyPublisher<[MBEvent], Never>

    /// Live stream of calendars paired with the active provider name.
    var calendarsPublisher: AnyPublisher<([MBCalendar], EventStoreProvider), Never>

    // MARK: - Commands

    /// Trigger a fresh calendar + event fetch from the active provider.
    /// Results flow back through `eventsPublisher` / `calendarsPublisher`.
    var triggerRefresh: @MainActor () -> Void

    /// Reconcile system notification requests with the current event plan.
    var reconcileNotifications: @MainActor ([MBEvent]) async -> Void

    /// Switch the active calendar provider.  `signOut = true` drops the current session first.
    var changeProvider: @MainActor (EventStoreProvider, Bool) async -> Void

    /// Current wall-clock time (injectable for tests).
    var now: @Sendable () -> Date

    // MARK: - Production default

    @MainActor
    static func live(
        eventManager: EventManager,
        notificationScheduler: NotificationScheduler
    ) -> AppEnvironment {
        AppEnvironment(
            eventsPublisher: eventManager.$events.eraseToAnyPublisher(),
            calendarsPublisher: eventManager.$calendars
                .map { calendars in
                    (calendars, eventManager.repository.activeProviderName)
                }
                .eraseToAnyPublisher(),
            triggerRefresh: {
                eventManager.refreshSubject.send()
            },
            reconcileNotifications: { events in
                await notificationScheduler.reconcile(
                    events: events,
                    settings: .currentForScheduler
                )
            },
            changeProvider: { newProvider, signOut in
                await eventManager.changeEventStoreProvider(newProvider, withSignOut: signOut)
            },
            now: { Date() }
        )
    }
}
