//
//  AppModel.swift
//  MeetingBar
//

import Combine
import Foundation

/// The central application model that owns `AppState` and handles `AppAction`s.
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

        // Subscribe to live event and calendar streams.
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

    // MARK: - Action dispatch

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

    // MARK: - Private

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            environment.triggerRefresh()
        }
    }
}
