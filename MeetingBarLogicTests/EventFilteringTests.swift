//
//  EventFilteringTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class EventFilteringTests: XCTestCase {
    private func settings(
        filterEventRegexes: [String] = [],
        allDayEvents: EventFilterAllDayMode = .show,
        nonAllDayEvents: EventFilterNonAllDayMode = .show,
        hidesPendingEvents: Bool = false,
        hidesTentativeEvents: Bool = false,
        hidesDeclinedEvents: Bool = false
    ) -> EventFilterSettings {
        EventFilterSettings(
            filterEventRegexes: filterEventRegexes,
            allDayEvents: allDayEvents,
            nonAllDayEvents: nonAllDayEvents,
            hidesPendingEvents: hidesPendingEvents,
            hidesTentativeEvents: hidesTentativeEvents,
            hidesDeclinedEvents: hidesDeclinedEvents
        )
    }

    private func event(
        id: String,
        title: String? = nil,
        sourceIndex: Int = 0,
        isAllDay: Bool = false,
        hasMeetingLink: Bool = true,
        participationStatus: EventFilterEvent.ParticipationStatus = .active
    ) -> EventFilterEvent {
        EventFilterEvent(
            sourceIndex: sourceIndex,
            id: id,
            title: title ?? id,
            isAllDay: isAllDay,
            hasMeetingLink: hasMeetingLink,
            participationStatus: participationStatus
        )
    }

    private func filteredIDs(
        _ events: [EventFilterEvent],
        settings: EventFilterSettings? = nil
    ) -> [String] {
        EventFiltering
            .filter(events, settings: settings ?? self.settings())
            .map(\.id)
    }

    func testFilteredDoesNotExcludePastOrFutureByItself() {
        let first = event(id: "past")
        let second = event(id: "future")
        XCTAssertEqual(filteredIDs([first, second]), ["past", "future"])
    }

    func testFilteredHidesDeclinedEventsWhenHideEnabled() {
        let declined = event(id: "declined", participationStatus: .declined)
        let ok = event(id: "ok")

        XCTAssertEqual(
            filteredIDs([declined, ok], settings: settings(hidesDeclinedEvents: true)),
            ["ok"]
        )
    }

    func testFilteredHidesAllDayEventsWhenHideEnabled() {
        let allDay = event(id: "allDay", isAllDay: true)
        let nonAllDay = event(id: "nonAllDay")

        XCTAssertEqual(
            filteredIDs([allDay, nonAllDay], settings: settings(allDayEvents: .hide)),
            ["nonAllDay"]
        )
    }

    func testFilteredHidesNonAllDayEventsWithoutLinkWhenHideEnabled() {
        let allDay = event(id: "allDay", isAllDay: true)
        let nonAllDay = event(id: "nonAllDay", hasMeetingLink: false)

        XCTAssertEqual(
            filteredIDs([allDay, nonAllDay], settings: settings(nonAllDayEvents: .hideWithoutMeetingLink)),
            ["allDay"]
        )
    }

    func testFilteredHidesPendingEventsWhenHideEnabled() {
        let pending = event(id: "pending", participationStatus: .pending)
        let confirmed = event(id: "confirmed")

        XCTAssertEqual(
            filteredIDs([pending, confirmed], settings: settings(hidesPendingEvents: true)),
            ["confirmed"]
        )
    }

    func testFilteredShowsAllDayWithLinkOnlyWhenSettingEnabled() {
        let allDayWithLink = event(id: "allDayWithLink", isAllDay: true, hasMeetingLink: true)
        let allDayWithoutLink = event(id: "allDayWithoutLink", isAllDay: true, hasMeetingLink: false)
        let nonAllDay = event(id: "nonAllDay")

        XCTAssertEqual(
            filteredIDs([allDayWithLink, allDayWithoutLink, nonAllDay], settings: settings(allDayEvents: .showWithMeetingLinkOnly)),
            ["allDayWithLink", "nonAllDay"]
        )
    }

    func testFilteredHidesTentativeEventsWhenHideEnabled() {
        let tentative = event(id: "tentative", participationStatus: .tentative)
        let confirmed = event(id: "confirmed")

        XCTAssertEqual(
            filteredIDs([tentative, confirmed], settings: settings(hidesTentativeEvents: true)),
            ["confirmed"]
        )
    }

    func testFilteredIncludesCanceledEventsBecauseSelectionHandlesCancellation() {
        let canceled = event(id: "canceled")
        let confirmed = event(id: "confirmed")
        XCTAssertEqual(filteredIDs([canceled, confirmed]), ["canceled", "confirmed"])
    }

    func testFilteredExcludesAllEventsMatchingRegex() {
        let first = event(id: "filterout1", title: "filterout")
        let second = event(id: "filterout2", title: "filterout")
        let other = event(id: "other")

        XCTAssertEqual(
            filteredIDs([first, second, other], settings: settings(filterEventRegexes: ["filterout"])),
            ["other"]
        )
    }
}
