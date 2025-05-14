//
//  EventManagerTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import XCTest
import Defaults
@testable import MeetingBar

class EventManagerTests: XCTestCase {
    func test_stream_emitsFilteredAndSortedEvents() async throws {
        let ev1 = makeFakeEvent(id: "e1", start: Date().addingTimeInterval(300), end: Date().addingTimeInterval(400))
        let ev2 = makeFakeEvent(id: "e1", start: Date().addingTimeInterval(100), end: Date().addingTimeInterval(200))
        let calendars = [ev1.calendar, ev2.calendar]
        let fake = await FakeEventStore(calendars: calendars, events: [ev1, ev2])

        let manager = EventManager(provider: fake)

        try await manager.loadCalendars()
        let firstBatch = await manager.stream().first(where: { _ in true })

        XCTAssertEqual(firstBatch, [ev2, ev1])  // sorted by startDate
    }
}
