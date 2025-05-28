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

    init(calendars: [MBCalendar] = [], events: [MBEvent] = []) {
        stubbedCalendars = calendars
        stubbedEvents = events
    }

    // MARK: - EventStore

    func fetchAllCalendars() async throws -> [MBCalendar] {
        stubbedCalendars
    }

    func fetchEventsForDateRange(
        for _: [MBCalendar],
        from _: Date,
        to _: Date
    ) async throws -> [MBEvent] {
        stubbedEvents
    }

    func refreshSources() async { /* no-op */ }
    func signIn() async throws { /* no-op */ }
    func signOut() async { /* no-op */ }
}
