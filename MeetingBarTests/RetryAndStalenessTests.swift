//
//  RetryAndStalenessTests.swift
//  MeetingBar
//
//  Tests for exponential backoff retry logic and staleness-based refresh gating.
//

import Combine
import Defaults
@testable import MeetingBar
import XCTest

// MARK: - Retry Logic Tests

@MainActor
final class RetryLogicTests: BaseTestCase {

    private var cancellables = Set<AnyCancellable>()

    /// When the store always throws, EventManager should retry up to 5 times
    /// per refresh cycle and ultimately publish empty calendars/events.
    func test_retryExhaustsAfterFiveAttempts() {
        let store = FakeEventStore()
        store.errorToThrow = NSError(domain: "TestError", code: 1)

        let manager = EventManager(provider: store, refreshInterval: 0, baseRetryDelay: 0.01)

        let exp = expectation(description: "retries exhausted")

        // The init triggers at least one refresh cycle (5 attempts).
        // Defaults observers may trigger additional cycles.
        // We verify that fetchCalendarsCallCount is a multiple of 5
        // (each cycle = 5 attempts) and signIn is called 4 times per cycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let cycles = store.fetchCalendarsCallCount / 5
            XCTAssertGreaterThanOrEqual(cycles, 1,
                           "Expected at least one full retry cycle (5 attempts)")
            XCTAssertEqual(store.fetchCalendarsCallCount, cycles * 5,
                           "Expected exactly 5 fetch attempts per cycle")
            XCTAssertEqual(store.signInCallCount, cycles * 4,
                           "Expected 4 signIn calls per cycle (retries 2-5)")
            exp.fulfill()
        }

        wait(for: [exp], timeout: 5.0)
    }

    /// When the store fails transiently and then recovers, EventManager should
    /// publish the successful result after retrying.
    func test_retrySucceedsAfterTransientFailures() {
        let fakeCal = MBCalendar(title: "Work", id: "work_cal", source: nil, email: nil, color: .blue)
        let fakeEvt = makeFakeEvent(
            id: "retry_event",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(3600)
        )

        let store = FakeEventStore(calendars: [fakeCal], events: [fakeEvt])
        store.errorToThrow = NSError(domain: "TestError", code: 1)
        store.succeedAfterFailures = 3  // fail 3 times, then succeed on attempt 4

        Defaults[.selectedCalendarIDs] = ["work_cal"]

        let manager = EventManager(provider: store, refreshInterval: 0, baseRetryDelay: 0.01)

        let calExp = expectation(description: "calendars published after retry")
        manager.$calendars
            .drop(while: \.isEmpty)
            .first()
            .sink { cals in
                XCTAssertEqual(cals.count, 1)
                XCTAssertEqual(cals.first?.id, "work_cal")
                calExp.fulfill()
            }
            .store(in: &cancellables)

        let evtExp = expectation(description: "events published after retry")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { evts in
                XCTAssertEqual(evts.count, 1)
                XCTAssertEqual(evts.first?.id, "retry_event")
                evtExp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [calExp, evtExp], timeout: 5.0)

        // At least one cycle succeeded: 3 failures + 1 success = 4 calls minimum
        XCTAssertGreaterThanOrEqual(store.fetchCalendarsCallCount, 4,
                       "Expected at least 4 fetch attempts (3 failures + 1 success)")
        // signIn called on retries only (at least attempts 2, 3) = at least 2 per cycle
        XCTAssertGreaterThanOrEqual(store.signInCallCount, 2,
                       "Expected signIn to be called on retry attempts")
    }

    /// When the store succeeds on first try, no retries or signIn calls happen.
    func test_noRetryOnSuccess() {
        let fakeCal = MBCalendar(title: "Cal", id: "cal1", source: nil, email: nil, color: .red)
        let fakeEvt = makeFakeEvent(
            id: "ok_event",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(3600)
        )

        let store = FakeEventStore(calendars: [fakeCal], events: [fakeEvt])
        Defaults[.selectedCalendarIDs] = ["cal1"]

        let manager = EventManager(provider: store, refreshInterval: 0, baseRetryDelay: 0.01)

        let exp = expectation(description: "events published without retry")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { evts in
                XCTAssertEqual(evts.count, 1)
                exp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [exp], timeout: 2.0)

        // Only 1 call, no retries
        XCTAssertEqual(store.fetchCalendarsCallCount, 1)
        // signIn is never called when the first attempt succeeds
        XCTAssertEqual(store.signInCallCount, 0)
    }
}

// MARK: - Staleness Tests

@MainActor
final class StalenessTests: BaseTestCase {

    private var cancellables = Set<AnyCancellable>()

    /// triggerRefresh should skip if the last refresh was recent (within 15 min).
    func test_triggerRefreshSkipsWhenFresh() {
        let store = FakeEventStore(
            calendars: [MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)],
            events: [makeFakeEvent(id: "S1", start: Date().addingTimeInterval(60), end: Date().addingTimeInterval(3600))]
        )
        Defaults[.selectedCalendarIDs] = ["c1"]

        let manager = EventManager(provider: store, refreshInterval: 0, baseRetryDelay: 0.01)

        // Wait for initial load to complete
        let initialExp = expectation(description: "initial load")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        wait(for: [initialExp], timeout: 2.0)

        let countAfterInitial = store.fetchCalendarsCallCount

        // Simulate a recent refresh by setting lastSuccessfulRefresh to now
        manager.setLastSuccessfulRefresh(Date())

        // Now swap events so we can detect if a refresh actually happens
        store.stubbedEvents = [makeFakeEvent(id: "S2", start: Date().addingTimeInterval(120), end: Date().addingTimeInterval(7200))]

        // triggerRefresh should be a no-op since we just refreshed
        manager.triggerRefresh()

        // Give some time for a potential (unwanted) refresh
        let skipExp = expectation(description: "no refresh happened")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // fetchCalendarsCallCount should not have increased
            XCTAssertEqual(store.fetchCalendarsCallCount, countAfterInitial,
                           "Expected no additional fetch when data is fresh")
            // Events should still be S1, not S2
            XCTAssertEqual(manager.events.first?.id, "S1",
                           "Events should not have changed when refresh was skipped")
            skipExp.fulfill()
        }
        wait(for: [skipExp], timeout: 2.0)
    }

    /// triggerRefresh should proceed when data is stale (last refresh > 15 min ago).
    func test_triggerRefreshProceedsWhenStale() {
        let store = FakeEventStore(
            calendars: [MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)],
            events: [makeFakeEvent(id: "Old", start: Date().addingTimeInterval(60), end: Date().addingTimeInterval(3600))]
        )
        Defaults[.selectedCalendarIDs] = ["c1"]

        let manager = EventManager(provider: store, refreshInterval: 0, baseRetryDelay: 0.01)

        // Wait for initial load
        let initialExp = expectation(description: "initial load")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        wait(for: [initialExp], timeout: 2.0)

        // Simulate stale data: last refresh was 20 minutes ago
        manager.setLastSuccessfulRefresh(Date().addingTimeInterval(-1200))

        // Swap to new events
        let newEvt = makeFakeEvent(id: "New", start: Date().addingTimeInterval(120), end: Date().addingTimeInterval(7200))
        store.stubbedEvents = [newEvt]

        // triggerRefresh should actually fire since data is stale
        let refreshExp = expectation(description: "stale refresh happened")
        manager.$events
            .dropFirst()
            .first()
            .sink { evts in
                XCTAssertEqual(evts.first?.id, "New",
                               "Expected new events after stale triggerRefresh")
                refreshExp.fulfill()
            }
            .store(in: &cancellables)

        manager.triggerRefresh()

        wait(for: [refreshExp], timeout: 2.0)
    }
}
