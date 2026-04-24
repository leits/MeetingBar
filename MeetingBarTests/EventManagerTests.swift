//
//  EventManagerTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import Combine
@testable import MeetingBar
import XCTest
import Defaults

@MainActor
class EventManagerTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    func testInjectedStorePublishesCalendarsAndEvents() {
        // 1) Prepare fakes
        let fakeCal = MBCalendar(title: "Cal A", id: "calA", source: nil, email: nil, color: .black)
        let fakeEvt = makeFakeEvent(
            id: "E1",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(3600)
        )
        let fakeStore = FakeEventStore(
            calendars: [fakeCal],
            events: [fakeEvt]
        )

        // 2) Create manager with test initializer
        let manager = EventManager(
            provider: fakeStore,
            refreshInterval: 0.05
        )

        // 3) Observe first non-empty values of calendars & events
        let calExpectation = expectation(description: "calendars published")
        manager.$calendars
            .drop(while: \.isEmpty)
            .first()
            .sink { cals in
                XCTAssertEqual(cals, [fakeCal])
                calExpectation.fulfill()
            }
            .store(in: &cancellables)

        let evtExpectation = expectation(description: "events published")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { evts in
                XCTAssertEqual(evts, [fakeEvt])
                evtExpectation.fulfill()
            }
            .store(in: &cancellables)

        // 4) Wait
        wait(for: [calExpectation, evtExpectation], timeout: 1.0)
    }
}

@MainActor class EventManagerSwitchProviderTests: BaseTestCase {

    private var cancellables = Set<AnyCancellable>()

    func testSwitchProviderPublishesNewEvents() async throws {
        // Arrange: two fake stores with different events
        let firstEvent  = makeFakeEvent(
            id: "A",
            start: Date(),
            end: Date().addingTimeInterval(3600)
        )
        let secondEvent = makeFakeEvent(
            id: "B",
            start: Date().addingTimeInterval(7200),
            end: Date().addingTimeInterval(10_800)
        )

        let storeA = FakeEventStore(events: [firstEvent])
        let storeB = FakeEventStore(events: [secondEvent])

        // Start EventManager with Store A
        let manager = EventManager(provider: storeA, refreshInterval: 0)

        // Expect the first publication to contain [firstEvent]
        let initialExp = expectation(description: "initial events")
        manager.$events
            .drop(while: \.isEmpty)
            .first()                                     // Failure == Never
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { events in
                    XCTAssertEqual(events, [firstEvent])
                    initialExp.fulfill()
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [initialExp], timeout: 1.0)

        // Prepare second expectation BEFORE switching the store
        let switchedExp = expectation(description: "events after switch")
        manager.$events
            .dropFirst()                                // skip current value
            .first()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { events in
                    XCTAssertEqual(events, [secondEvent])
                    switchedExp.fulfill()
                }
            )
            .store(in: &cancellables)

        // Act: replace the provider and trigger refresh
        manager.provider = storeB
        try await manager.refreshSources()              // sends refreshSubject

        await fulfillment(of: [switchedExp], timeout: 1.0)

    }
}

@MainActor
final class FailedRefreshTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    private let fakeCal = MBCalendar(title: "Cal", id: "calA", source: nil, email: nil, color: .black)

    func test_failedRefreshPreservesExistingCalendars() async throws {
        let store = FakeEventStore(calendars: [fakeCal])
        let manager = EventManager(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial calendars loaded")
        manager.$calendars.drop(while: \.isEmpty).first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        store.stubbedError = NSError(domain: "test", code: 1)

        let preservedExp = expectation(description: "calendars preserved after failure")
        manager.$calendars.dropFirst().first()
            .sink { cals in
                XCTAssertEqual(cals, [self.fakeCal], "calendars must not be cleared on refresh failure")
                preservedExp.fulfill()
            }
            .store(in: &cancellables)

        try await manager.refreshSources()
        await fulfillment(of: [preservedExp], timeout: 1.0)
    }

    func test_failedRefreshPreservesExistingEvents() async throws {
        let fakeEvt = makeFakeEvent(id: "E1", start: Date().addingTimeInterval(60), end: Date().addingTimeInterval(3600))
        let store = FakeEventStore(calendars: [fakeCal], events: [fakeEvt])

        Defaults[.selectedCalendarIDs] = ["calA"]
        let manager = EventManager(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial events loaded")
        manager.$events.drop(while: \.isEmpty).first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        store.stubbedError = NSError(domain: "test", code: 1)

        let preservedExp = expectation(description: "events preserved after failure")
        manager.$events.dropFirst().first()
            .sink { evts in
                XCTAssertEqual(evts, [fakeEvt], "events must be the exact preserved set after refresh failure")
                preservedExp.fulfill()
            }
            .store(in: &cancellables)

        try await manager.refreshSources()
        await fulfillment(of: [preservedExp], timeout: 1.0)
    }

    func test_failedInitialRefreshDoesNotCrash() {
        let store = FakeEventStore()
        store.stubbedError = NSError(domain: "test", code: 1)
        let manager = EventManager(provider: store, refreshInterval: 0)

        let exp = expectation(description: "brief wait after failed initial refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(manager.calendars, [])
        XCTAssertEqual(manager.events, [])
    }
}

@MainActor
final class RefreshCoalescingTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    func test_rapidTriggersResultInSingleFetch() async throws {
        let fakeCal = MBCalendar(title: "Cal", id: "calA", source: nil, email: nil, color: .black)
        let store = FakeEventStore(calendars: [fakeCal])
        store.fetchDelay = 0.2 // slow enough that the fetch is still running when the rapid triggers arrive

        let manager = EventManager(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial load")
        manager.$calendars.drop(while: \.isEmpty).first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 2.0)

        let countBefore = store.fetchCallCount

        // Fire three triggers in rapid succession — only the first should start a fetch
        manager.refreshSubject.send()
        manager.refreshSubject.send()
        manager.refreshSubject.send()

        // Wait longer than fetchDelay so the single fetch can complete
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(store.fetchCallCount - countBefore, 1, "only one fetch should run despite three triggers")
    }
}

@MainActor
final class RefreshTriggerTests: BaseTestCase {

    private var cancellables = Set<AnyCancellable>()

    func test_eventsRefreshWhenShowEventsPeriodChanges() {
        // Fake store that can swap its stubbed events on the fly
        let first  = makeFakeEvent(id: "P-A",
                                   start: .init(),
                                   end: .init().addingTimeInterval(60))
        let second = makeFakeEvent(id: "P-B",
                                   start: .init().addingTimeInterval(120),
                                   end: .init().addingTimeInterval(240))

        let store = FakeEventStore(events: [first])

        // Start with `.today`
        Defaults[.showEventsForPeriod] = .today
        let manager = EventManager(provider: store, refreshInterval: 0)

        // Expect initial publication with [first]
        let initialExp = expectation(description: "initial events")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { events in
                XCTAssertEqual(events, [first])
                initialExp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [initialExp], timeout: 1.0)

        // Prepare expectation BEFORE flipping the Default
        let switchedExp = expectation(description: "events after period change")
        manager.$events
            .dropFirst()            // skip current value
            .first()
            .sink { events in
                XCTAssertEqual(events, [second])
                switchedExp.fulfill()
            }
            .store(in: &cancellables)

        // ↻ Mutate store, then toggle Default → Combine trigger fires
        store.stubbedEvents = [second]
        Defaults[.showEventsForPeriod] = .today_n_tomorrow

        wait(for: [switchedExp], timeout: 1.0)
    }

    func test_refreshSourcesPublishesEvents() async throws {
        let ev = makeFakeEvent(id: "R",
                               start: .init(),
                               end: .init().addingTimeInterval(60))
        let store = FakeEventStore(events: [ev])
        let manager = EventManager(provider: store, refreshInterval: 0)

        // Expectation BEFORE calling refreshSources()
        let exp = expectation(description: "events after manual refresh")
        manager.$events
            .dropFirst()          // skip the initial []
            .first()              // grab only the first non-empty publish
            .sink { events in
                XCTAssertEqual(events, [ev])
                exp.fulfill()
            }
            .store(in: &cancellables)

        // Act
        try await manager.refreshSources()

        await fulfillment(of: [exp], timeout: 1)
    }
}

@MainActor
final class ProviderHealthTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    func test_successfulRefreshClearsError() async throws {
        let store = FakeEventStore(calendars: [MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)])
        let manager = EventManager(provider: store, refreshInterval: 0)

        let exp = expectation(description: "health after success")
        manager.$providerHealth
            .drop(while: { $0.lastAttemptedRefresh == nil })
            .first()
            .sink { health in
                XCTAssertNotNil(health.lastSuccessfulRefresh)
                XCTAssertNil(health.lastErrorDescription)
                XCTAssertFalse(health.isStale)
                exp.fulfill()
            }
            .store(in: &cancellables)

        await fulfillment(of: [exp], timeout: 1.0)
    }

    func test_failedRefreshSetsErrorAndPreservesLastSuccess() async throws {
        let store = FakeEventStore(calendars: [MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)])
        let manager = EventManager(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial success")
        manager.$providerHealth
            .drop(while: { $0.lastSuccessfulRefresh == nil })
            .first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        let lastSuccess = manager.providerHealth.lastSuccessfulRefresh
        store.stubbedError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "network gone"])

        let failExp = expectation(description: "health after failure")
        manager.$providerHealth
            .dropFirst()
            .first()
            .sink { health in
                XCTAssertEqual(health.lastSuccessfulRefresh, lastSuccess, "prior success date must be preserved")
                XCTAssertNotNil(health.lastErrorDescription)
                XCTAssertTrue(health.isStale)
                failExp.fulfill()
            }
            .store(in: &cancellables)

        try await manager.refreshSources()
        await fulfillment(of: [failExp], timeout: 1.0)
    }
}
