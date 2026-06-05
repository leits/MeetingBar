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

// MARK: - Clock

/// One place for workflow code to ask "what time is it?"
///
/// The app still formats dates directly in views where that is presentation
/// work. AppModel decisions use this clock so tests can make time-sensitive
/// behavior deterministic.
struct AppClock {
    var now: @Sendable () -> Date

    static let live = AppClock(now: { Date() })

    static func fixed(_ date: Date) -> AppClock {
        AppClock(now: { date })
    }
}

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
    func nextEvent(now: Date, linkRequired: Bool = false) -> MBEvent? {
        events.nextEvent(linkRequired: linkRequired, now: now)
    }
}

// MARK: - Routing

enum AppRoute: Equatable {
    case preferences
    case oauthCallback(URL)
    case unknown(URL)
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
    case selectCalendar(id: String, selected: Bool)

    // Settings
    case settingsChanged
    case toggleMeetingTitleVisibility

    // Provider
    /// Switch the active calendar provider.  `signOut = true` drops the current OAuth session first.
    case changeProvider(EventStoreProvider, signOut: Bool)

    // Notification responses
    case notificationResponse(NotificationResponseAction)
    case joinMeeting(eventID: String)
    case joinNearestMeeting
    case dismissMeeting(eventID: String)
    case dismissNearestMeeting
    case undismissMeeting(eventID: String)
    case clearDismissedMeetings
    case snoozeMeeting(eventID: String, action: NotificationEventTimeAction)

    // Onboarding / external routes
    case onboardingCompleted(EventStoreProvider)
    case openRoute(AppRoute)

    // Notification reconcile
    case reconcileNotifications
}

// MARK: - Environment

/// Injectable side-effect wiring used by `AppModel`.
///
/// Production code injects the real app components; tests inject fakes.
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

    /// Add or remove a calendar from the user's selection. EventManager
    /// observes the underlying setting and re-fetches automatically.
    var toggleCalendarSelection: @MainActor (String, Bool) -> Void

    /// Open the meeting for an event. Later PRs move every entry point onto
    /// this route; for now it lets AppModel own the action vocabulary.
    var openMeeting: @MainActor (MBEvent) -> Void

    /// Dismiss an event from next-meeting workflows.
    var dismissEvent: @MainActor (MBEvent) -> Void

    /// Remove one event dismissal.
    var undismissEvent: @MainActor (String) -> Void

    /// Remove all event dismissals.
    var clearDismissedEvents: @MainActor () -> Void

    /// Toggle whether meeting names are hidden in status bar/menu surfaces.
    var toggleMeetingTitleVisibility: @MainActor () -> Void

    /// Snooze an event notification.
    var snoozeEvent: @MainActor (MBEvent, NotificationEventTimeAction) async -> Void

    /// Finish onboarding by persisting completion and selecting the provider.
    var completeOnboarding: @MainActor (EventStoreProvider) async -> Void

    /// Open Preferences from an app URL route.
    var openPreferences: @MainActor () -> Void

    /// Resume an OAuth callback from an app URL route.
    var resumeOAuthFlow: @MainActor (URL) -> Void

    /// Current wall-clock time for workflow decisions.
    var clock: AppClock

    @MainActor
    static func live(
        eventManager: EventManager,
        notificationScheduler: NotificationScheduler,
        snoozeService: SnoozeService,
        openPreferences: @escaping @MainActor () -> Void = {},
        resumeOAuthFlow: @escaping @MainActor (URL) -> Void = { _ in }
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
            toggleCalendarSelection: { id, selected in
                AppSettings.setCalendarSelection(id: id, selected: selected)
            },
            openMeeting: { event in
                MeetingOpener.open(event: event)
            },
            dismissEvent: { event in
                AppSettings.dismissEvent(event)
            },
            undismissEvent: { eventID in
                AppSettings.undismissEvent(id: eventID)
            },
            clearDismissedEvents: {
                AppSettings.clearDismissedEvents()
            },
            toggleMeetingTitleVisibility: {
                AppSettings.toggleMeetingTitleVisibility()
            },
            snoozeEvent: { event, action in
                await snoozeService.snooze(event: event, action: action)
            },
            completeOnboarding: { provider in
                AppSettings.completeOnboarding()
                await eventManager.changeEventStoreProvider(provider)
            },
            openPreferences: openPreferences,
            resumeOAuthFlow: resumeOAuthFlow,
            clock: .live
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
        case .launched, .willTerminate, .screenLocked, .screenUnlocked,
             .didWake, .timezoneChanged, .dayChanged:
            handleLifecycleAction(action)
        case .calendarStoreChanged, .refreshCalendars, .calendarsLoaded,
             .eventsLoaded, .calendarRefreshFailed, .providerChanged,
             .selectCalendar, .changeProvider, .settingsChanged,
             .toggleMeetingTitleVisibility:
            handleCalendarAction(action)
        case .notificationResponse, .joinMeeting, .joinNearestMeeting, .dismissMeeting,
             .dismissNearestMeeting, .undismissMeeting, .clearDismissedMeetings,
             .snoozeMeeting:
            handleMeetingAction(action)
        case .onboardingCompleted, .openRoute:
            handleExternalAction(action)
        case .reconcileNotifications:
            reconcileNotificationsFromState()
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

    /// Add or remove a calendar from the user's selection. Routes through
    /// `AppEnvironment` so the model stays free of `Defaults` writes.
    func toggleCalendarSelection(id: String, selected: Bool) {
        send(.selectCalendar(id: id, selected: selected))
    }

    func nextEvent(linkRequired: Bool = false) -> MBEvent? {
        state.nextEvent(now: environment.clock.now(), linkRequired: linkRequired)
    }

    /// Onboarding is an async workflow because provider authorization can
    /// prompt the user. The action case still exists for non-blocking routes,
    /// while AppDelegate awaits this method before moving the onboarding UI on.
    func completeOnboarding(with provider: EventStoreProvider) async {
        state.activeProvider = provider
        state.calendars = []
        state.events = []
        await environment.completeOnboarding(provider)
    }

    // MARK: Private

    private func event(withID id: String) -> MBEvent? {
        state.events.first { $0.id == id }
    }

    private func handleLifecycleAction(_ action: AppAction) {
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
        case .didWake, .timezoneChanged, .dayChanged:
            scheduleRefresh()
        default:
            break
        }
    }

    private func handleCalendarAction(_ action: AppAction) {
        switch action {
        case .calendarStoreChanged, .refreshCalendars, .settingsChanged:
            scheduleRefresh()
        case .toggleMeetingTitleVisibility:
            environment.toggleMeetingTitleVisibility()
        case .calendarsLoaded(let calendars, let provider):
            state.calendars = calendars
            state.activeProvider = provider
        case .eventsLoaded(let events):
            state.events = events
            send(.reconcileNotifications)
        case .calendarRefreshFailed:
            break
        case .providerChanged(let provider):
            resetProviderState(to: provider)
            scheduleRefresh()
        case .selectCalendar(let id, let selected):
            environment.toggleCalendarSelection(id, selected)
        case .changeProvider(let provider, let signOut):
            resetProviderState(to: provider)
            Task {
                await environment.changeProvider(provider, signOut)
            }
        default:
            break
        }
    }

    private func handleMeetingAction(_ action: AppAction) {
        switch action {
        case .notificationResponse(let response):
            switch response {
            case .join(let eventID):
                send(.joinMeeting(eventID: eventID))
            case .dismiss(let eventID):
                send(.dismissMeeting(eventID: eventID))
            case .snooze(let eventID, let action):
                send(.snoozeMeeting(eventID: eventID, action: action))
            }
        case .joinMeeting(let eventID):
            performWithEvent(id: eventID) { event in
                environment.openMeeting(event)
            }
        case .joinNearestMeeting:
            if let event = state.nextEvent(now: environment.clock.now()) {
                environment.openMeeting(event)
            }
        case .dismissMeeting(let eventID):
            performWithEvent(id: eventID) { event in
                environment.dismissEvent(event)
            }
        case .dismissNearestMeeting:
            if let event = state.nextEvent(now: environment.clock.now()) {
                environment.dismissEvent(event)
            }
        case .undismissMeeting(let eventID):
            environment.undismissEvent(eventID)
        case .clearDismissedMeetings:
            environment.clearDismissedEvents()
        case .snoozeMeeting(let eventID, let action):
            guard let event = event(withID: eventID) else { return }
            Task {
                await environment.snoozeEvent(event, action)
            }
        default:
            break
        }
    }

    private func handleExternalAction(_ action: AppAction) {
        switch action {
        case .onboardingCompleted(let provider):
            Task {
                await completeOnboarding(with: provider)
            }
        case .openRoute(let route):
            handleRoute(route)
        default:
            break
        }
    }

    private func handleRoute(_ route: AppRoute) {
        switch route {
        case .preferences:
            environment.openPreferences()
        case .oauthCallback(let url):
            environment.resumeOAuthFlow(url)
        case .unknown:
            break
        }
    }

    private func performWithEvent(id: String, perform: (MBEvent) -> Void) {
        guard let event = event(withID: id) else { return }
        perform(event)
    }

    private func reconcileNotificationsFromState() {
        let events = state.events
        Task {
            await environment.reconcileNotifications(events)
        }
    }

    private func resetProviderState(to provider: EventStoreProvider) {
        state.activeProvider = provider
        state.calendars = []
        state.events = []
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            environment.triggerRefresh()
        }
    }
}
