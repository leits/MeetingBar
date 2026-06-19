//
//  AdapterMappingTests.swift
//  MeetingBarTests
//
//  Characterization tests for the Defaults → logic-type adapter layer.
//  These tests pin the exact mapping between Defaults enums and the pure
//  Core types so that a mistake during the SettingsStore migration (Stage 3)
//  is caught automatically rather than discovered in production.
//
//  Coverage:
//    EventFiltering+MeetingBar  — EventFilterSettings.current
//    StatusBarPresentation+MeetingBar — StatusBarPresentationSettings.current,
//                                       StatusBarTimeDisplay init,
//                                       StatusBarEventTitleFormat init,
//                                       StatusBarParticipationDisplay init
//

import Defaults
import XCTest

@testable import MeetingBar

// MARK: - EventFilterSettings adapter

@MainActor
final class EventFilterSettingsAdapterTests: BaseTestCase {

    // MARK: allDayEvents

    func test_allDayEvents_show_mapsToShow() {
        Defaults[.allDayEvents] = .show
        XCTAssertEqual(EventFilterSettings.current.allDayEvents, .show)
    }

    func test_allDayEvents_showWithLinkOnly_mapsToShowWithMeetingLinkOnly() {
        Defaults[.allDayEvents] = .show_with_meeting_link_only
        XCTAssertEqual(EventFilterSettings.current.allDayEvents, .showWithMeetingLinkOnly)
    }

    func test_allDayEvents_hide_mapsToHide() {
        Defaults[.allDayEvents] = .hide
        XCTAssertEqual(EventFilterSettings.current.allDayEvents, .hide)
    }

    // MARK: nonAllDayEvents

    func test_nonAllDayEvents_show_mapsToShow() {
        Defaults[.nonAllDayEvents] = .show
        XCTAssertEqual(EventFilterSettings.current.nonAllDayEvents, .show)
    }

    func test_nonAllDayEvents_showInactiveWithoutLink_mapsToShow() {
        // show_inactive_without_meeting_link is a visual hint only —
        // the event is still shown, so the filter mode stays .show.
        Defaults[.nonAllDayEvents] = .show_inactive_without_meeting_link
        XCTAssertEqual(EventFilterSettings.current.nonAllDayEvents, .show)
    }

    func test_nonAllDayEvents_hideWithoutLink_mapsToHideWithoutMeetingLink() {
        Defaults[.nonAllDayEvents] = .hide_without_meeting_link
        XCTAssertEqual(EventFilterSettings.current.nonAllDayEvents, .hideWithoutMeetingLink)
    }

    // MARK: pending events

    func test_showPendingEvents_hide_setsHidesPendingTrue() {
        Defaults[.showPendingEvents] = .hide
        XCTAssertTrue(EventFilterSettings.current.hidesPendingEvents)
    }

    func test_showPendingEvents_show_setsHidesPendingFalse() {
        Defaults[.showPendingEvents] = .show
        XCTAssertFalse(EventFilterSettings.current.hidesPendingEvents)
    }

    func test_showPendingEvents_showInactive_setsHidesPendingFalse() {
        Defaults[.showPendingEvents] = .show_inactive
        XCTAssertFalse(EventFilterSettings.current.hidesPendingEvents)
    }

    func test_showPendingEvents_showUnderlined_setsHidesPendingFalse() {
        Defaults[.showPendingEvents] = .show_underlined
        XCTAssertFalse(EventFilterSettings.current.hidesPendingEvents)
    }

    // MARK: tentative events

    func test_showTentativeEvents_hide_setsHidesTentativeTrue() {
        Defaults[.showTentativeEvents] = .hide
        XCTAssertTrue(EventFilterSettings.current.hidesTentativeEvents)
    }

    func test_showTentativeEvents_show_setsHidesTentativeFalse() {
        Defaults[.showTentativeEvents] = .show
        XCTAssertFalse(EventFilterSettings.current.hidesTentativeEvents)
    }

    // MARK: declined events

    func test_declinedEventsAppereance_hide_setsHidesDeclinedTrue() {
        Defaults[.declinedEventsAppereance] = .hide
        XCTAssertTrue(EventFilterSettings.current.hidesDeclinedEvents)
    }

    func test_declinedEventsAppereance_strikethrough_setsHidesDeclinedFalse() {
        Defaults[.declinedEventsAppereance] = .strikethrough
        XCTAssertFalse(EventFilterSettings.current.hidesDeclinedEvents)
    }

    func test_declinedEventsAppereance_showInactive_setsHidesDeclinedFalse() {
        Defaults[.declinedEventsAppereance] = .show_inactive
        XCTAssertFalse(EventFilterSettings.current.hidesDeclinedEvents)
    }

    // MARK: filterEventRegexes pass-through

    func test_filterEventRegexes_passedThrough() {
        Defaults[.filterEventRegexes] = ["standup", #"[Dd]aily"#]
        XCTAssertEqual(EventFilterSettings.current.filterEventRegexes, ["standup", #"[Dd]aily"#])
    }

    func test_filterEventRegexes_emptyByDefault() {
        XCTAssertTrue(EventFilterSettings.current.filterEventRegexes.isEmpty)
    }
}

// MARK: - StatusBarPresentationSettings adapter

@MainActor
final class StatusBarPresentationSettingsAdapterTests: BaseTestCase {

    func test_noSelectedCalendars_setsHasSelectedCalendarsFalse() {
        Defaults[.selectedCalendarIDs] = []
        XCTAssertFalse(StatusBarPresentationSettings.current.hasSelectedCalendars)
    }

    func test_withSelectedCalendars_setsHasSelectedCalendarsTrue() {
        Defaults[.selectedCalendarIDs] = ["cal-1", "cal-2"]
        XCTAssertTrue(StatusBarPresentationSettings.current.hasSelectedCalendars)
    }

    func test_showEventMaxTimeUntilEventEnabled_passedThrough() {
        Defaults[.showEventMaxTimeUntilEventEnabled] = true
        XCTAssertTrue(StatusBarPresentationSettings.current.showEventMaxTimeUntilEventEnabled)

        Defaults[.showEventMaxTimeUntilEventEnabled] = false
        XCTAssertFalse(StatusBarPresentationSettings.current.showEventMaxTimeUntilEventEnabled)
    }

    func test_showEventMaxTimeUntilEventThreshold_passedThrough() {
        Defaults[.showEventMaxTimeUntilEventThreshold] = 45
        XCTAssertEqual(StatusBarPresentationSettings.current.showEventMaxTimeUntilEventThreshold, 45)
    }
}

// MARK: - StatusBarTimeDisplay init mapping

final class StatusBarTimeDisplayMappingTests: XCTestCase {

    func test_show_mapsToShow() {
        XCTAssertEqual(StatusBarTimeDisplay(.show), .show)
    }

    func test_showUnderTitle_mapsToShowUnderTitle() {
        XCTAssertEqual(StatusBarTimeDisplay(.show_under_title), .showUnderTitle)
    }

    func test_hide_mapsToHide() {
        XCTAssertEqual(StatusBarTimeDisplay(.hide), .hide)
    }
}

// MARK: - StatusBarEventTitleFormat init mapping

final class StatusBarEventTitleFormatMappingTests: XCTestCase {

    func test_show_mapsToShow() {
        XCTAssertEqual(StatusBarEventTitleFormat(.show), .show)
    }

    func test_dot_mapsToDot() {
        XCTAssertEqual(StatusBarEventTitleFormat(.dot), .dot)
    }

    func test_none_mapsToNone() {
        XCTAssertEqual(StatusBarEventTitleFormat(.none), .none)
    }
}

// MARK: - StatusBarParticipationDisplay init mapping

final class StatusBarParticipationDisplayMappingTests: XCTestCase {

    // MARK: PendingEventsAppereance

    func test_pendingShow_mapsToNormal() {
        XCTAssertEqual(StatusBarParticipationDisplay(PendingEventsAppereance.show), .normal)
    }

    func test_pendingShowInactive_mapsToInactive() {
        XCTAssertEqual(StatusBarParticipationDisplay(PendingEventsAppereance.show_inactive), .inactive)
    }

    func test_pendingShowUnderlined_mapsToUnderlined() {
        XCTAssertEqual(StatusBarParticipationDisplay(PendingEventsAppereance.show_underlined), .underlined)
    }

    func test_pendingHide_mapsToNormal() {
        // .hide means the event is hidden at the filter layer; if it somehow
        // reaches the presenter, display it normally.
        XCTAssertEqual(StatusBarParticipationDisplay(PendingEventsAppereance.hide), .normal)
    }

    // MARK: TentativeEventsAppereance

    func test_tentativeShow_mapsToNormal() {
        XCTAssertEqual(StatusBarParticipationDisplay(TentativeEventsAppereance.show), .normal)
    }

    func test_tentativeShowInactive_mapsToInactive() {
        XCTAssertEqual(StatusBarParticipationDisplay(TentativeEventsAppereance.show_inactive), .inactive)
    }

    func test_tentativeShowUnderlined_mapsToUnderlined() {
        XCTAssertEqual(StatusBarParticipationDisplay(TentativeEventsAppereance.show_underlined), .underlined)
    }

    func test_tentativeHide_mapsToNormal() {
        XCTAssertEqual(StatusBarParticipationDisplay(TentativeEventsAppereance.hide), .normal)
    }
}

// MARK: - EventFilterEvent init from MBEvent

@MainActor
final class EventFilterEventAdapterTests: BaseTestCase {

    func test_eventWithMeetingLink_hasMeetingLinkTrue() {
        let event = MBEvent(
            id: "E1",
            lastModifiedDate: nil,
            title: "Standup",
            status: .confirmed,
            notes: nil,
            location: nil,
            url: URL(string: "https://zoom.us/j/123456"),
            organizer: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            isAllDay: false,
            recurrent: false,
            calendar: MBCalendar(title: "Cal", id: "c1", source: nil, email: nil, color: .black)
        )

        let filterEvent = EventFilterEvent(event: event, sourceIndex: 0)

        XCTAssertTrue(filterEvent.hasMeetingLink)
        XCTAssertEqual(filterEvent.id, "E1")
        XCTAssertEqual(filterEvent.title, "Standup")
        XCTAssertFalse(filterEvent.isAllDay)
    }

    func test_eventWithoutMeetingLink_hasMeetingLinkFalse() {
        let event = MBEvent(
            id: "E2",
            lastModifiedDate: nil,
            title: "Lunch",
            status: .confirmed,
            notes: nil,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            isAllDay: false,
            recurrent: false,
            calendar: MBCalendar(title: "Cal", id: "c1", source: nil, email: nil, color: .black)
        )

        let filterEvent = EventFilterEvent(event: event, sourceIndex: 1)

        XCTAssertFalse(filterEvent.hasMeetingLink)
    }

    func test_participationStatus_pending_mapsToPending() {
        var event = makeFakeEvent(
            id: "P1",
            start: Date(),
            end: Date().addingTimeInterval(3600)
        )
        event.participationStatus = .pending

        let filterEvent = EventFilterEvent(event: event, sourceIndex: 0)

        XCTAssertEqual(filterEvent.participationStatus, .pending)
    }

    func test_participationStatus_declined_mapsToDeclined() {
        var event = makeFakeEvent(
            id: "D1",
            start: Date(),
            end: Date().addingTimeInterval(3600)
        )
        event.participationStatus = .declined

        let filterEvent = EventFilterEvent(event: event, sourceIndex: 0)

        XCTAssertEqual(filterEvent.participationStatus, .declined)
    }

    func test_participationStatus_delegated_mapsToActive() {
        var event = makeFakeEvent(
            id: "DG1",
            start: Date(),
            end: Date().addingTimeInterval(3600)
        )
        event.participationStatus = .delegated

        let filterEvent = EventFilterEvent(event: event, sourceIndex: 0)

        XCTAssertEqual(filterEvent.participationStatus, .active)
    }
}
