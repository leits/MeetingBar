//
//  StatusBarPresentationPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class StatusBarPresentationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let assets = StatusBarIconAssets(
        appIcon: "AppIcon",
        calendarCheckmark: "iconCalendarCheckmark",
        calendar: "iconCalendar"
    )

    private func settings(
        hasSelectedCalendars: Bool = true,
        showEventMaxTimeUntilEventEnabled: Bool = false,
        threshold: Int = 30
    ) -> StatusBarPresentationSettings {
        StatusBarPresentationSettings(
            hasSelectedCalendars: hasSelectedCalendars,
            showEventMaxTimeUntilEventEnabled: showEventMaxTimeUntilEventEnabled,
            showEventMaxTimeUntilEventThreshold: threshold
        )
    }

    private func presenterSettings(
        hasSelectedCalendars: Bool = true,
        titleFormat: StatusBarEventTitleFormat = .show,
        titleLength: Int = 55,
        timeDisplay: StatusBarTimeDisplay = .show,
        iconFormat: StatusBarIconFormat = .none,
        pendingDisplay: StatusBarParticipationDisplay = .normal,
        tentativeDisplay: StatusBarParticipationDisplay = .normal,
        compactTitleLimit: Int = 28
    ) -> StatusBarPresenterSettings {
        StatusBarPresenterSettings(
            presentation: settings(hasSelectedCalendars: hasSelectedCalendars),
            title: StatusBarTitleSettings(
                titleFormat: titleFormat,
                hideMeetingTitle: false,
                titleLength: titleLength,
                labels: StatusBarTitleLabels(
                    genericMeetingTitle: "Meeting",
                    noTitle: "No title",
                    activeEventTimeFormat: "now (%@ left)",
                    upcomingEventTimeFormat: "in %@"
                )
            ),
            timeDisplay: timeDisplay,
            iconFormat: iconFormat,
            iconFormatAssetName: "no_online_session",
            iconAssets: assets,
            pendingDisplay: pendingDisplay,
            tentativeDisplay: tentativeDisplay,
            compactTitleLimit: compactTitleLimit
        )
    }

    private func event(
        title: String? = "Weekly sync",
        meetingService: MeetingServices? = .zoom,
        participation: StatusBarEventParticipation = .normal
    ) -> StatusBarEventPresentationInput {
        StatusBarEventPresentationInput(
            title: title,
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(2400),
            meetingService: meetingService,
            participation: participation
        )
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func testIdleWhenNoCalendarsSelected() {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(60),
            settings: settings(hasSelectedCalendars: false),
            now: now
        )
        XCTAssertEqual(mode, .idle,
                       "no calendars selected → idle regardless of any next event")
    }

    func testNoUpcomingWhenSelectedButNoEvent() {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: nil,
            settings: settings(),
            now: now
        )
        XCTAssertEqual(mode, .noUpcoming)
    }

    func testNextEventWhenThresholdDisabled() {
        // Even an event 12 hours away renders as "next" when the threshold
        // toggle is off — that is the legacy default behavior.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(43_200),
            settings: settings(showEventMaxTimeUntilEventEnabled: false),
            now: now
        )
        XCTAssertEqual(mode, .nextEvent)
    }

    func testNextEventWhenWithinThreshold() {
        // Threshold 30 min, event 10 min away → within threshold → render
        // as next event with title.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(600),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .nextEvent)
    }

    func testAfterThresholdWhenBeyondThreshold() {
        // Threshold 30 min, event 45 min away → past threshold → alarm hint.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(2700),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .afterThreshold)
    }

    func testOngoingEventCountsAsNextEvent() {
        // An event that started 5 min ago (timeUntilStart < 0) is below
        // any positive threshold and should render as the current next event.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(-300),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .nextEvent,
                       "negative timeUntilStart is always within any positive threshold")
    }

    func testThresholdBoundaryIsExclusive() {
        // Threshold 30 min, event exactly 30 min away → not strictly less
        // than the threshold → afterThreshold. Documents the existing
        // boundary semantics inherited from updateTitle().
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(1800),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .afterThreshold)
    }

    func testPresenterPreservesRTLTitleWithInlineTime() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(title: "פגישת צוות"),
            settings: presenterSettings(timeDisplay: .show),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.title, "פגישת צוות")
        XCTAssertEqual(presentation.layout, .inline(showTime: true))
    }

    func testPresenterUsesStackedLayoutForTimeUnderTitle() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(),
            settings: presenterSettings(timeDisplay: .showUnderTitle),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.layout, .stacked)
        XCTAssertFalse(presentation.time.isEmpty)
    }

    func testPresenterCompactsLongTitleAndAddsIconFallback() {
        let longTitle = String(repeating: "Very long meeting title ", count: 8)
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(title: longTitle, meetingService: .zoom),
            settings: presenterSettings(titleLength: 200, iconFormat: .none, compactTitleLimit: 28),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.icon, .meetingService(.zoom))
        XCTAssertTrue(presentation.title.hasSuffix("..."))
        XCTAssertTrue(presentation.compactFallback)
    }

    func testPresenterAvoidsBlankStatusWhenTitleAndIconAreDisabled() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(title: "Weekly sync", meetingService: nil),
            settings: presenterSettings(titleFormat: .none, timeDisplay: .hide, iconFormat: .none),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.title, "•")
        XCTAssertEqual(presentation.icon, .meetingService(nil))
        XCTAssertEqual(presentation.layout, .inline(showTime: false))
        XCTAssertTrue(presentation.compactFallback)
    }

    func testPresenterMarksPendingStackedTitleInactive() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(participation: .pending),
            settings: presenterSettings(timeDisplay: .showUnderTitle, pendingDisplay: .inactive),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.titleStyle, .inactive)
    }
}
