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
    var stubbedCalendars: [MBCalendar]
    var stubbedEvents: [MBEvent]

    /// When non-nil, `fetchAllCalendars()` throws this error.
    var errorToThrow: Error?

    /// Counts how many times `fetchAllCalendars()` has been called.
    var fetchCalendarsCallCount = 0

    /// Counts how many times `signIn(forcePrompt:)` has been called.
    var signInCallCount = 0

    /// When set, `errorToThrow` is cleared after this many failures,
    /// allowing subsequent calls to succeed (simulates transient failures).
    var succeedAfterFailures: Int?

    init(calendars: [MBCalendar] = [], events: [MBEvent] = []) {
        stubbedCalendars = calendars
        stubbedEvents = events
    }

    // MARK: - EventStore

    func fetchAllCalendars() async throws -> [MBCalendar] {
        fetchCalendarsCallCount += 1
        if let error = errorToThrow {
            if let threshold = succeedAfterFailures,
               fetchCalendarsCallCount > threshold {
                // Stop throwing after enough failures
            } else {
                throw error
            }
        }
        return stubbedCalendars
    }

    func fetchEventsForDateRange(
        for _: [MBCalendar],
        from _: Date,
        to _: Date
    ) async throws -> [MBEvent] {
        stubbedEvents
    }

    func refreshSources() async { /* no-op */ }
    func signIn(forcePrompt: Bool = false) async throws {
        signInCallCount += 1
    }
    func signOut() async { /* no-op */ }
}
