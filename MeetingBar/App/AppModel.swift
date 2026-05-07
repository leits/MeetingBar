//
//  AppModel.swift
//  MeetingBar
//
//  Owns `AppState`, dispatches `AppAction`s, and routes side effects through
//  `AppEnvironment`. `AppState`, `AppAction`, and `AppEnvironment` live here
//  too because they exist solely to serve this type.
//

import Combine
import Foundation

// MARK: - State

/// Complete observable state of the application at a point in time.
///
/// `AppState` is value-typed and derived from lower-level sources of truth
/// (`EventManager`, `AppSettings`, system state). Renderers (status bar,
/// menus, notifications) read from `AppState` rather than reaching through
/// managers directly.
struct AppState: Equatable {
    // MARK: Calendar

    var calendars: [MBCalendar] = []
    var events: [MBEvent] = []
    var activeProvider: EventStoreProvider = .macOSEventKit

    // MARK: System

    /// `true` while the screen is locked or the display is off.
    var screenIsLocked: Bool = false

    // MARK: Derived

    /// Next upcoming event that has not been dismissed and is not all-day.
    var nextEvent: MBEvent? {
        events.first { !$0.isAllDay && $0.endDate > Date() }
    }
}

// MARK: - Action

/// All events that change application state.
///
/// Dispatched to `AppModel.send(_:)`; never carries
/// AppKit/UserNotifications/EventKit types so the model stays testable
/// without a running host app.
enum AppAction {
    // Lifecycle
    case launched
    case willTerminate

    // System events
    case screenLocked
    case screenUnlocked
    case didWake
    case timezoneChanged
    case dayChanged

    // Calendar
    case calendarStoreChanged
    case refreshCalendars
    case calendarsLoaded([MBCalendar], provider: EventStoreProvider)
    case eventsLoaded([MBEvent])
    case calendarRefreshFailed(Error)
    case providerChanged(EventStoreProvider)

    // Settings
    case settingsChanged

    // Provider
    /// Switch the active calendar provider.  `signOut = true` drops the current OAuth session first.
    case changeProvider(EventStoreProvider, signOut: Bool)

    // Notification responses
    case joinMeeting(eventID: String)
    case dismissMeeting(eventID: String)
    case snoozeMeeting(eventID: String, action: NotificationEventTimeAction)

    // Notification reconcile
    case reconcileNotifications
}

// MARK: - Environment

/// Injectable side-effect clients used by `AppModel`.
///
/// Production code injects the real implementations; tests inject fakes.
/// `AppEnvironment` must not import AppKit, EventKit, UserNotifications, or
/// AppAuth so that `AppModel` remains hostless-testable.
struct AppEnvironment {
    /// Live stream of the current event list from the active provider.
    var eventsPublisher: AnyPublisher<[MBEvent], Never>

    /// Live stream of calendars paired with the active provider name.
    var calendarsPublisher: AnyPublisher<([MBCalendar], EventStoreProvider), Never>

    /// Trigger a fresh calendar + event fetch from the active provider.
    /// Results flow back through `eventsPublisher` / `calendarsPublisher`.
    var triggerRefresh: @MainActor () -> Void

    /// Reconcile system notification requests with the current event plan.
    var reconcileNotifications: @MainActor ([MBEvent]) async -> Void

    /// Switch the active calendar provider. `signOut = true` drops the current session first.
    var changeProvider: @MainActor (EventStoreProvider, Bool) async -> Void

    /// Current wall-clock time (injectable for tests).
    var now: @Sendable () -> Date

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

// MARK: - Model

/// Central application model.
///
/// `AppModel` must not import AppKit, EventKit, UserNotifications, or AppAuth.
/// All side effects are performed through `AppEnvironment`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AppState = AppState()

    private let environment: AppEnvironment
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment

        // `@Published` delivers the current value immediately on subscription,
        // so AppModel is up-to-date even if EventManager already fetched.
        environment.eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.send(.eventsLoaded(events))
            }
            .store(in: &cancellables)

        environment.calendarsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (calendars, provider) in
                self?.send(.calendarsLoaded(calendars, provider: provider))
            }
            .store(in: &cancellables)
    }

    // MARK: Action dispatch

    func send(_ action: AppAction) {
        switch action {
        case .launched:
            scheduleRefresh()

        case .willTerminate:
            refreshTask?.cancel()

        case .screenLocked:
            state.screenIsLocked = true

        case .screenUnlocked:
            state.screenIsLocked = false
            scheduleRefresh()

        case .didWake, .timezoneChanged, .dayChanged, .calendarStoreChanged:
            scheduleRefresh()

        case .refreshCalendars:
            scheduleRefresh()

        case .calendarsLoaded(let calendars, let provider):
            state.calendars = calendars
            state.activeProvider = provider

        case .eventsLoaded(let events):
            state.events = events
            send(.reconcileNotifications)

        case .calendarRefreshFailed:
            // preserve last known events
            break

        case .providerChanged(let provider):
            state.activeProvider = provider
            state.calendars = []
            state.events = []
            scheduleRefresh()

        case .settingsChanged:
            scheduleRefresh()

        case .changeProvider(let provider, let signOut):
            state.activeProvider = provider
            state.calendars = []
            state.events = []
            Task {
                await environment.changeProvider(provider, signOut)
            }

        case .reconcileNotifications:
            let events = state.events
            Task {
                await environment.reconcileNotifications(events)
            }

        case .joinMeeting, .dismissMeeting, .snoozeMeeting:
            // Response actions handled by NotificationCenterDelegate for now.
            break
        }
    }

    // MARK: Convenience methods for system triggers

    /// Self-documenting wrappers around `send(_:)` for the most common
    /// system-event paths. Callers don't need to import `AppAction` to
    /// route a wake/lock/timezone change through the model.
    func handleLaunch() { send(.launched) }
    func handleWillTerminate() { send(.willTerminate) }
    func handleScreenLock() { send(.screenLocked) }
    func handleScreenUnlock() { send(.screenUnlocked) }
    func handleWake() { send(.didWake) }
    func handleTimezoneChange() { send(.timezoneChanged) }
    func handleDayChange() { send(.dayChanged) }
    func handleCalendarStoreChange() { send(.calendarStoreChanged) }
    func requestRefresh() { send(.refreshCalendars) }
    func reconcileNotifications() { send(.reconcileNotifications) }

    // MARK: Private

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            environment.triggerRefresh()
        }
    }
}
