//
//  EventManager.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import Cocoa
import Combine
import Defaults
import EventKit
import Foundation
import UserNotifications

public enum EventManagerError: Error {
    case eventStoreNotAvailable
    case calendarAccessFailed(Error)
    case eventFetchFailed(Error)
}

@MainActor
public class EventManager: ObservableObject {
    @Published public private(set) var calendars: [MBCalendar] = []
    @Published public private(set) var events: [MBEvent] = []

    var provider: EventStore
    private let refreshInterval: TimeInterval
    private var cancellables = Set<AnyCancellable>()
    private let refreshSubject = PassthroughSubject<Void, Never>()

    private var storeChangeCancellable: AnyCancellable?

    // MARK: - Initialization

    public init(refreshInterval: TimeInterval = 180) async {
        self.refreshInterval = refreshInterval
        provider = await MainActor.run {
            switch Defaults[.eventStoreProvider] {
            case .macOSEventKit: return EKEventStore.shared
            case .googleCalendar: return GCEventStore.shared
            }
        }
        await configureProvider(Defaults[.eventStoreProvider])
        setupPublishers()
        refreshSubject.send() // initial load
    }

    public func changeEventStoreProvider(_ newProvider: EventStoreProvider, withSignOut: Bool = false) async {
        Defaults[.eventStoreProvider] = newProvider
        Defaults[.selectedCalendarIDs] = []
        calendars = []

        if withSignOut {
            await provider.signOut()
        }

        await configureProvider(newProvider)

        // immediately reload everything
        do {
            try await provider.signIn()
            refreshSubject.send()
        } catch {
            NSLog("Error after switching provider: \(error)")
        }
    }

    private func configureProvider(_ providerName: EventStoreProvider) async {
        storeChangeCancellable?.cancel()
        storeChangeCancellable = nil

        switch providerName {
        case .macOSEventKit:
            let store = await MainActor.run { EKEventStore.shared }
            provider = store

            // observe EKEventStoreChanged
            storeChangeCancellable = NotificationCenter.default
                .publisher(for: .EKEventStoreChanged, object: store)
                // we only need the notification to fire; do the actual work in Swift concurrency
                .sink { [weak self] _ in
                    Task {
                        do {
                            try await self?.refreshSources()
                        } catch {
                            NSLog("Failed reloading calendars: \(error)")
                        }
                    }
                }

        case .googleCalendar:
            let store = await MainActor.run { GCEventStore.shared }
            provider = store
        }
    }

    public func refreshSources() async throws {
        await provider.refreshSources()
        refreshSubject.send()
    }

    /// Fetches events for the selected calendars within the specified date range
    private func fetchEvents(fromCalendars: [MBCalendar]) async throws -> [MBEvent] {
        let dateFrom = Calendar.current.startOfDay(for: Date())
        var dateTo: Date

        switch Defaults[.showEventsForPeriod] {
        case .today:
            dateTo = Calendar.current.date(byAdding: .day, value: 1, to: dateFrom)!
        case .today_n_tomorrow:
            dateTo = Calendar.current.date(byAdding: .day, value: 2, to: dateFrom)!
        }

        let selectedCalendars = fromCalendars.filter { Defaults[.selectedCalendarIDs].contains($0.id) }

        let rawEvents: [MBEvent]
        do {
            rawEvents = try await provider.fetchEventsForDateRange(for: selectedCalendars,
                                                                   from: dateFrom,
                                                                   to: dateTo)
        } catch {
            throw EventManagerError.eventFetchFailed(error)
        }

        // Update dismissed events in case the event end date has changed.
        if !Defaults[.dismissedEvents].isEmpty {
            var dismissedEvents: [ProcessedEvent] = []
            for dismissedEvent in Defaults[.dismissedEvents] {
                if let event = rawEvents.first(where: { $0.id == dismissedEvent.id }), event.endDate.timeIntervalSinceNow > 0 {
                    dismissedEvents.append(ProcessedEvent(id: event.id, eventEndDate: event.endDate))
                }
            }
            Defaults[.dismissedEvents] = dismissedEvents
        }
        return rawEvents.filtered().sorted { $0.startDate < $1.startDate }
    }

    private func setupPublishers() {
        // A) Defaults changes as an “empty” trigger
        let defaultsPub = Defaults.publisher(keys:
            .selectedCalendarIDs,
            .showEventsForPeriod,
            .customRegexes,
            .declinedEventsAppereance,
            .showPendingEvents,
            .showTentativeEvents,
            .allDayEvents,
            .nonAllDayEvents, options: []).map { _ in () }.eraseToAnyPublisher()

        // B) Periodic timer trigger
        let timerPub: AnyPublisher<Void, Never>
        if refreshInterval > 0 {
            timerPub = Timer
                .publish(every: refreshInterval, on: .main, in: .common)
                .autoconnect()
                .map { _ in () }
                .eraseToAnyPublisher()
        } else {
            timerPub = Empty().eraseToAnyPublisher()
        }

        // C) Manual trigger
        let manualPub = refreshSubject.eraseToAnyPublisher()

        // D) Merge them all
        let trigger = Publishers.Merge3(defaultsPub, timerPub, manualPub)

        // E) When any fires, fetch calendars & events
        trigger
            .flatMap { [weak self] _ -> AnyPublisher<([MBCalendar], [MBEvent]), Never> in
                guard let self = self else {
                    return Just(([], [])).eraseToAnyPublisher()
                }
                return Deferred {
                    Future<([MBCalendar], [MBEvent]), Error> { promise in
                        Task {
                            do {
                                let cals = try await self.provider.fetchAllCalendars()
                                let evts = try await self.fetchEvents(fromCalendars: cals)
                                promise(.success((cals, evts)))
                            } catch {
                                NSLog("EventManager refresh failed: \(error)")
                                promise(.success(([], [])))
                            }
                        }
                    }
                }
                .catch { error -> Empty<([MBCalendar], [MBEvent]), Never> in
                    NSLog("EventManager refresh failed: \(error)")
                    return Empty(completeImmediately: true)
                }
                .eraseToAnyPublisher()
            }
            // **important: hop back to the main run-loop before assigning**
            .receive(on: RunLoop.main)
            .sink { [weak self] cals, evts in
                // now we’re safely on the main actor / main thread
                self?.calendars = cals
                self?.events = evts
            }
            .store(in: &cancellables)
    }

    #if DEBUG
        /// Test-only initializer: inject your own store and skip
        /// the async system-store configuration.
        public init(provider: EventStore,
                    refreshInterval: TimeInterval = 0) {
            self.refreshInterval = refreshInterval
            self.provider = provider
            // no storeChangeCancellable for real notifications
            setupPublishers()
            refreshSubject.send()
        }
    #endif
}
