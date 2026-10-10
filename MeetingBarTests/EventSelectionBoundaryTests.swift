import Defaults
import XCTest

@testable import MeetingBar

@MainActor
final class EventSelectionBoundaryTests: BaseTestCase {
    private let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)

    private func events() -> [MBEvent] {
        [
            makeFakeEvent(
                id: "pending", start: now.addingTimeInterval(300),
                end: now.addingTimeInterval(600), withLink: true, participationStatus: .pending
            ),
            makeFakeEvent(
                id: "accepted", start: now.addingTimeInterval(1200),
                end: now.addingTimeInterval(1800), withLink: true
            )
        ]
    }

    private func displaySettings(pending: PendingEventsAppereance) -> EventDisplaySettings {
        var settings = AppSettings.current.events
        settings.showPendingEvents = pending
        settings.personalEventsAppearance = .show_active
        settings.dismissedEvents = []
        return settings
    }

    func testStateSelectionUsesSuppliedSettingsDespiteDefaultsChanges() {
        let state = AppState(events: events())
        let settings = EventSelectionSettings(displaySettings(pending: .show))

        Defaults[.showPendingEvents] = .hide
        XCTAssertEqual(state.nextEvent(settings: settings, now: now)?.id, "pending")
        Defaults[.personalEventsAppereance] = .hide
        XCTAssertEqual(state.nextEvent(settings: settings, now: now)?.id, "pending")
    }

    func testMenuSelectionUsesTheSameSettingsSnapshotAsItsDisplay() {
        let state = AppState(events: events())
        var settings = AppSettings.current
        settings.events = displaySettings(pending: .show)
        Defaults[.showPendingEvents] = .hide

        let menu = StatusBarMenuState.make(from: state, settings: settings, now: now)

        XCTAssertEqual(menu.nextEvent?.id, "pending")
        XCTAssertEqual(menu.settings.events.showPendingEvents, .show)
    }

    func testNearestActionsReadFreshInjectedSettings() {
        let harness = AppModelTestHarness(now: now)
        defer { harness.model.handleWillTerminate() }
        harness.model.send(.eventsLoaded(events()))
        Defaults[.showPendingEvents] = .hide

        harness.selectionSettings = EventSelectionSettings(displaySettings(pending: .show))
        XCTAssertEqual(harness.model.nextEvent()?.id, "pending")
        harness.model.send(.joinNearestMeeting)

        harness.selectionSettings = EventSelectionSettings(displaySettings(pending: .hide))
        XCTAssertEqual(harness.model.nextEvent()?.id, "accepted")
        harness.model.send(.joinNearestMeeting)
        harness.model.send(.dismissNearestMeeting)

        XCTAssertEqual(harness.openedMeetingIDs, ["pending", "accepted"])
        XCTAssertEqual(harness.dismissedEventIDs, ["accepted"])
    }
}
