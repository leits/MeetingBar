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
        self.stubbedCalendars = calendars
        self.stubbedEvents = events
    }

    func fetchAllCalendars() async throws -> [MBCalendar] {
        return stubbedCalendars
    }

    func fetchEventsForDateRange(for calendars: [MBCalendar],
                                 from: Date, to: Date) async throws -> [MBEvent] {
        return stubbedEvents
    }

    func refreshSources() async {
        // no-op
    }

    func signIn() async throws {
        // no-op
    }

    func signOut() async {
        // no-op
    }
}
