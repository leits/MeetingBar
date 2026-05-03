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

    init(environment: AppEnvironment) {
        self.environment = environment
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

        case let .calendarsLoaded(calendars, provider):
            state.calendars = calendars
            state.activeProvider = provider

        case let .eventsLoaded(events):
            state.events = events

        case .calendarRefreshFailed:
            // preserve last known events, could log/report health here
            break

        case let .providerChanged(provider):
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
            guard let self else { return }
            let (calendars, provider) = await environment.refreshCalendars()
            guard !Task.isCancelled else { return }
            send(.calendarsLoaded(calendars, provider: provider))

            let events = await environment.refreshEvents(calendars)
            guard !Task.isCancelled else { return }
            send(.eventsLoaded(events))
            send(.reconcileNotifications)
        }
    }
}
