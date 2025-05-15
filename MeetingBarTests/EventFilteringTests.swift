//
//  EventFilteringTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Defaults
@testable import MeetingBar
import XCTest

final class EventFilteringTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset all the toggles to their “show everything” defaults
        Defaults[.declinedEventsAppereance] = .show_inactive
        Defaults[.pastEventsAppereance] = .show_inactive
        Defaults[.allDayEvents] = .show
        Defaults[.nonAllDayEvents] = .show
        Defaults[.showPendingEvents] = .show
    }

    func test_filtered_excludesPastEvents() {
        let now = Date()
        let past = makeFakeEvent(id: "past",
                                 start: now.addingTimeInterval(-3600),
                                 end: now.addingTimeInterval(-1800))
        let future = makeFakeEvent(id: "future",
                                   start: now.addingTimeInterval(1800),
                                   end: now.addingTimeInterval(3600))

        let result = [past, future].filtered()
        XCTAssertEqual(result.map(\.id), ["past", "future"])
    }

    func test_filtered_hidesDeclinedEvents_whenHideEnabled() {
        Defaults[.declinedEventsAppereance] = .hide
        var declined = makeFakeEvent(id: "declined",
                                     start: Date().addingTimeInterval(600),
                                     end: Date().addingTimeInterval(1200))
        declined.participationStatus = .declined
        let ok = makeFakeEvent(id: "ok",
                               start: Date().addingTimeInterval(600),
                               end: Date().addingTimeInterval(1200))

        let result = [declined, ok].filtered()
        XCTAssertEqual(result.map(\.id), ["ok"])
    }

    func test_filtered_hidesAllDayEvents_whenHideEnabled() {
        Defaults[.allDayEvents] = .hide
        let allDay = makeFakeEvent(id: "allDay",
                                   start: Date(),
                                   end: Date().addingTimeInterval(86_400),
                                   isAllDay: true)
        let nonAllDay = makeFakeEvent(id: "nonAllDay",
                                      start: Date().addingTimeInterval(600),
                                      end: Date().addingTimeInterval(1200))

        let result = [allDay, nonAllDay].filtered()
        XCTAssertEqual(result.map(\.id), ["nonAllDay"])
    }

    func test_filtered_hidesNonAllDayEvents_whenHideEnabled() {
        Defaults[.nonAllDayEvents] = .hide_without_meeting_link
        let allDay = makeFakeEvent(id: "allDay",
                                   start: Date(),
                                   end: Date().addingTimeInterval(86_400),
                                   isAllDay: true)
        let nonAllDay = makeFakeEvent(id: "nonAllDay",
                                      start: Date().addingTimeInterval(600),
                                      end: Date().addingTimeInterval(1200))

        let result = [allDay, nonAllDay].filtered()
        XCTAssertEqual(result.map(\.id), ["allDay"])
    }

    func test_filtered_hidesPendingEvents_whenHideEnabled() {
        Defaults[.showPendingEvents] = .hide
        let pending = makeFakeEvent(id: "pending",
                                    start: Date().addingTimeInterval(600),
                                    end: Date().addingTimeInterval(1200),
                                    participationStatus: .pending)
        let confirmed = makeFakeEvent(id: "confirmed",
                                      start: Date().addingTimeInterval(600),
                                      end: Date().addingTimeInterval(1200))

        let result = [pending, confirmed].filtered()
        XCTAssertEqual(result.map(\.id), ["confirmed"])
    }
}
