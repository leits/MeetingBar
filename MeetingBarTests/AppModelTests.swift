//
//  AppModelTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class AppModelTests: BaseTestCase {
    func testLaunchTriggersRefresh() async {
        let harness = AppModelTestHarness()

        harness.model.send(.launched)
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.refreshCallCount, 1)
    }

    func testProviderChangeClearsStateAndDelegatesToEnvironment() async {
        let harness = AppModelTestHarness()
        let calendar = makeFakeCalendar(id: "cal")
        let event = makeFakeEvent(
            id: "event",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1_800)
        )
        harness.model.send(.calendarsLoaded([calendar], provider: .macOSEventKit))
        harness.model.send(.eventsLoaded([event]))

        harness.model.send(.changeProvider(.googleCalendar, signOut: true))
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.activeProvider, .googleCalendar)
        XCTAssertTrue(harness.model.state.calendars.isEmpty)
        XCTAssertTrue(harness.model.state.events.isEmpty)
        XCTAssertEqual(harness.providerChanges.map(\.provider), [.googleCalendar])
        XCTAssertEqual(harness.providerChanges.map(\.signOut), [true])
    }

    func testCalendarSelectionDelegatesToEnvironment() {
        let harness = AppModelTestHarness()

        harness.model.toggleCalendarSelection(id: "cal", selected: true)
        harness.model.toggleCalendarSelection(id: "cal", selected: false)

        XCTAssertEqual(harness.calendarSelections.map(\.id), ["cal", "cal"])
        XCTAssertEqual(harness.calendarSelections.map(\.selected), [true, false])
    }

    func testEventsLoadedUpdatesStateAndReconcilesNotifications() async {
        let harness = AppModelTestHarness()
        let event = makeFakeEvent(
            id: "event",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1_800)
        )

        harness.model.send(.eventsLoaded([event]))
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.events.map(\.id), ["event"])
        XCTAssertEqual(harness.reconciledEventIDs, [["event"]])
    }
}
