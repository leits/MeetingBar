//
//  EventManagerTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import XCTest
import Combine
@testable import MeetingBar

@MainActor
class EventManagerTests: XCTestCase {
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

  func testManualRefreshAfterSwappingStore() async {
    // 1) Start with one store…
    let initialStore = FakeEventStore(calendars: [], events: [])
    let manager = EventManager(provider: initialStore, refreshInterval: 0.05)

    // …then swap in a richer store
    let newCal = MBCalendar(title: "New", id: "newCal", source: nil, email: nil, color: .black)
    let newEvt = makeFakeEvent(id: "X", start: Date(), end: Date().addingTimeInterval(600))
    let newStore = FakeEventStore(calendars: [newCal], events: [newEvt])

    manager.provider = newStore   // inject…
     try! await manager.refreshSources() // …and manually trigger

    let expCal = expectation(description: "got swapped calendars")
    manager.$calendars
      .drop(while: \.isEmpty)
      .first()
      .sink { XCTAssertEqual($0, [newCal]); expCal.fulfill() }
      .store(in: &cancellables)

    let expEvt = expectation(description: "got swapped events")
    manager.$events
      .drop(while: \.isEmpty)
      .first()
      .sink { XCTAssertEqual($0, [newEvt]); expEvt.fulfill() }
      .store(in: &cancellables)

      await fulfillment(of: [expCal, expEvt], timeout: 1.0)
  }
}
