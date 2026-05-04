//
//  FakeEventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Foundation

@testable import MeetingBar

final class FakeEventStore: EventStore {
    nonisolated(unsafe) var stubbedCalendars: [MBCalendar]
    nonisolated(unsafe) var stubbedEvents: [MBEvent]
    nonisolated(unsafe) var stubbedError: Error?
    nonisolated(unsafe) var stubbedCalendarError: Error?
    nonisolated(unsafe) var stubbedEventsError: Error?
    nonisolated(unsafe) var fetchDelay: TimeInterval = 0
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    init(calendars: [MBCalendar] = [], events: [MBEvent] = []) {
        stubbedCalendars = calendars
        stubbedEvents = events
    }

    // MARK: - EventStore

    func fetchAllCalendars() async throws -> [MBCalendar] {
        fetchCallCount += 1
        if fetchDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(fetchDelay * 1_000_000_000))
        }
        if let error = stubbedCalendarError { throw error }
        if let error = stubbedError { throw error }
        return stubbedCalendars
    }

    func fetchEventsForDateRange(
        for _: [MBCalendar],
        from _: Date,
        to _: Date
    ) async throws -> [MBEvent] {
        if let error = stubbedEventsError { throw error }
        if let error = stubbedError { throw error }
        return stubbedEvents
    }

    func refreshSources() async { /* no-op */  }
}
