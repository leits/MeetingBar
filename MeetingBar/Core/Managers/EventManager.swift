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

public enum EventManagerError: LocalizedError {
    case eventStoreNotAvailable
    case calendarAccessFailed(Error)
    case eventFetchFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .eventStoreNotAvailable:
            return "Event store is not available"
        case let .calendarAccessFailed(error), let .eventFetchFailed(error):
            return error.localizedDescription
        }
    }
}

@MainActor
public class EventManager: ObservableObject {
    @Published public private(set) var calendars: [MBCalendar] = []
    @Published public private(set) var events: [MBEvent] = []
    @Published public private(set) var providerHealth = ProviderHealth()

    var repository: CalendarRepository
    private let refreshInterval: TimeInterval
    private var cancellables = Set<AnyCancellable>()
    let refreshSubject = PassthroughSubject<Void, Never>()

    // MARK: - Initialization

    public init(refreshInterval: TimeInterval = 180) async {
        self.refreshInterval = refreshInterval
        repository = CalendarRepository(providerName: Defaults[.eventStoreProvider])
        await configureProvider(Defaults[.eventStoreProvider])
        setupPublishers()
        refreshSubject.send() // initial load
    }

    public func changeEventStoreProvider(_ newProvider: EventStoreProvider, withSignOut: Bool = false) async {
        Defaults[.eventStoreProvider] = newProvider
        Defaults[.selectedCalendarIDs] = []
        calendars = []

        if withSignOut {
            await repository.signOut()
        }

        await repository.switchProvider(to: newProvider)

        // re-wire EKEventStore change notifications through the new repository
        subscribeToRepositoryStoreChanges()

        // immediately reload everything
        do {
            try await repository.signIn(forcePrompt: false)
            refreshSubject.send()
        } catch {
            NSLog("Error after switching provider: \(error)")
        }
    }

    private func configureProvider(_ providerName: EventStoreProvider) async {
        subscribeToRepositoryStoreChanges()
    }

    private func subscribeToRepositoryStoreChanges() {
        repository.storeChanged
            .sink { [weak self] in
                Task {
                    do {
                        try await self?.refreshSources()
                    } catch {
                        NSLog("Failed reloading calendars: \(error)")
                    }
                }
            }
            .store(in: &cancellables)
    }

    public func refreshSources() async throws {
        await repository.refreshSources()
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
            rawEvents = try await repository.fetchEventsForDateRange(for: selectedCalendars,
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

        // D) Merge all triggers; throttle drops bursts.
        // Throttle (not debounce) so the first trigger in a window passes through
        // immediately — manual refresh feels instant — while subsequent rapid
        // triggers (e.g. several Defaults changes in one preferences update) are
        // collapsed into a single fetch. debounce would also delay a fast periodic
        // timer indefinitely if its interval is shorter than the debounce window.
        let trigger = Publishers.Merge3(defaultsPub, timerPub, manualPub)
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: false)

        // E) When any fires, fetch calendars & events.
        // flatMap(maxPublishers: .max(1)) serializes fetches so at most one runs
        // at a time; if another trigger arrives during a fetch, it queues exactly once.
        trigger
            .flatMap(maxPublishers: .max(1)) { [weak self] _ -> AnyPublisher<([MBCalendar], [MBEvent], ProviderHealth), Never> in
                guard let self = self else {
                    return Just(([], [], ProviderHealth())).eraseToAnyPublisher()
                }
                // Capture current state on the main thread before entering the async Task.
                // On failure we republish these so the UI keeps showing last known data.
                let preservedCalendars = self.calendars
                let preservedEvents = self.events
                let previousHealth = self.providerHealth
                return Deferred {
                    Future<([MBCalendar], [MBEvent], ProviderHealth), Never> { promise in
                        Task {
                            let attempted = Date()
                            do {
                                let cals = try await self.repository.fetchAllCalendars()
                                let evts = try await self.fetchEvents(fromCalendars: cals)
                                let health = ProviderHealth.success(attempted: attempted)
                                promise(.success((cals, evts, health)))
                            } catch {
                                NSLog("EventManager refresh failed: \(error)")
                                let health = ProviderHealth.failure(
                                    previous: previousHealth,
                                    attempted: attempted,
                                    error: error
                                )
                                promise(.success((preservedCalendars, preservedEvents, health)))
                            }
                        }
                    }
                }
                .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] cals, evts, health in
                self?.calendars = cals
                self?.events = evts
                self?.providerHealth = health
            }
            .store(in: &cancellables)
    }

    #if DEBUG
        /// Test-only initializer: inject your own store and skip
        /// the async system-store configuration.
        public init(provider: EventStore,
                    refreshInterval: TimeInterval = 0) {
            self.refreshInterval = refreshInterval
            self.repository = CalendarRepository(store: provider)
            setupPublishers()
            refreshSubject.send()
        }
    #endif
}
