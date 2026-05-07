//
//  CalendarRepository.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import Combine
import Defaults
import EventKit
import Foundation

// MARK: - Date range helpers

func calendarDateRange(for period: ShowEventsForPeriod) -> (from: Date, to: Date) {
    let dateFrom = Calendar.current.startOfDay(for: Date())
    let dateTo: Date
    switch period {
    case .today:
        dateTo = Calendar.current.date(byAdding: .day, value: 1, to: dateFrom)!
    case .today_n_tomorrow:
        dateTo = Calendar.current.date(byAdding: .day, value: 2, to: dateFrom)!
    }
    return (dateFrom, dateTo)
}

/// Owns the active calendar provider and exposes calendar/event fetching.
///
/// `EventManager` delegates to `CalendarRepository` for all provider-specific
/// work so that provider selection is in one place. Future phases will move the
/// `EventManager` publishers into this type and have `AppModel` consume it
/// directly.
@MainActor
public final class CalendarRepository {
    // MARK: - Active provider

    public private(set) var activeProvider: EventStore
    public private(set) var activeProviderName: EventStoreProvider

    /// Fires when the EKEventStore changes (macOS Calendar App only).
    let storeChanged = PassthroughSubject<Void, Never>()
    private var storeChangeCancellable: AnyCancellable?

    // MARK: - Initialization

    public init(providerName: EventStoreProvider) {
        self.activeProviderName = providerName
        self.activeProvider = CalendarRepository.makeStore(for: providerName)
        observeStoreChanges(for: providerName)
    }

    // MARK: - Provider management

    public func switchProvider(to providerName: EventStoreProvider) async {
        storeChangeCancellable?.cancel()
        storeChangeCancellable = nil

        activeProviderName = providerName
        activeProvider = CalendarRepository.makeStore(for: providerName)
        observeStoreChanges(for: providerName)
    }

    // MARK: - Fetch

    public func fetchAllCalendars() async throws -> [MBCalendar] {
        try await activeProvider.fetchAllCalendars()
    }

    public func fetchEventsForDateRange(
        for calendars: [MBCalendar],
        from dateFrom: Date,
        to dateTo: Date
    ) async throws -> [MBEvent] {
        try await activeProvider.fetchEventsForDateRange(for: calendars, from: dateFrom, to: dateTo)
    }

    /// Fetches events for the currently configured display period and selected calendars.
    ///
    /// This is a convenience that consolidates date-range calculation and selected-calendar
    /// filtering so `EventManager` does not need to know about either detail.
    public func fetchCurrentPeriodEvents(fromAllCalendars allCalendars: [MBCalendar]) async throws
        -> [MBEvent] {
        let selectedCalendars = allCalendars.filter {
            Defaults[.selectedCalendarIDs].contains($0.id)
        }
        let (dateFrom, dateTo) = calendarDateRange(for: Defaults[.showEventsForPeriod])
        return try await activeProvider.fetchEventsForDateRange(
            for: selectedCalendars, from: dateFrom, to: dateTo)
    }

    public func refreshSources() async {
        await activeProvider.refreshSources()
    }

    // MARK: - Authenticated helpers

    public func signIn(forcePrompt: Bool = false) async throws {
        try await (activeProvider as? AuthenticatedEventStore)?.signIn(forcePrompt: forcePrompt)
    }

    public func signOut() async {
        await (activeProvider as? AuthenticatedEventStore)?.signOut()
    }

    /// Forwards an OAuth callback URL to the active provider if it supports it.
    ///
    /// Returns `true` if the URL was consumed by the active provider.
    @discardableResult
    public func resumeAuthorizationFlow(with url: URL) -> Bool {
        guard let store = activeProvider as? GCEventStore else { return false }
        return store.currentAuthorizationFlow?.resumeExternalUserAgentFlow(with: url) ?? false
    }

    #if DEBUG
        /// Test-only: inject a pre-built store without creating system singletons.
        public init(store: EventStore) {
            self.activeProviderName = .macOSEventKit
            self.activeProvider = store
        }
    #endif

    // MARK: - Private helpers

    private static func makeStore(for providerName: EventStoreProvider) -> EventStore {
        switch providerName {
        case .macOSEventKit: return EKEventStore.shared
        case .googleCalendar: return GCEventStore.shared
        }
    }

    private func observeStoreChanges(for providerName: EventStoreProvider) {
        guard providerName == .macOSEventKit else { return }
        let store = EKEventStore.shared
        storeChangeCancellable = NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: store)
            .map { _ in () }
            .sink { [weak self] in self?.storeChanged.send() }
    }
}
