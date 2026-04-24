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
    var stubbedError: Error?

    init(calendars: [MBCalendar] = [], events: [MBEvent] = []) {
        stubbedCalendars = calendars
        stubbedEvents = events
    }

    // MARK: - EventStore

    func fetchAllCalendars() async throws -> [MBCalendar] {
        if let error = stubbedError { throw error }
        return stubbedCalendars
    }

    func fetchEventsForDateRange(
        for _: [MBCalendar],
        from _: Date,
        to _: Date
    ) async throws -> [MBEvent] {
        if let error = stubbedError { throw error }
        return stubbedEvents
    }

    func refreshSources() async { /* no-op */ }
    func signIn(forcePrompt: Bool = false) async throws { /* no-op */ }
    func signOut() async { /* no-op */ }
}
