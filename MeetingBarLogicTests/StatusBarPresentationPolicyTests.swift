//
//  StatusBarPresentationTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class StatusBarPresentationTests: XCTestCase {
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

    // MARK: - Non-event modes (guard mode == .nextEvent, let nextEvent else)

    func testPresenterReturnsEmptyPresentationForIdleMode() {
        // hasSelectedCalendars: false → mode = .idle → guard fires
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(),
            settings: presenterSettings(hasSelectedCalendars: false),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.mode, .idle)
        XCTAssertEqual(presentation.title, "")
        XCTAssertEqual(presentation.time, "")
        XCTAssertNil(presentation.tooltip)
        XCTAssertEqual(presentation.layout, .none)
        XCTAssertFalse(presentation.removeDeliveredNotifications)
    }

    func testPresenterReturnsEmptyPresentationForNoUpcomingMode() {
        // nil nextEvent → mode = .noUpcoming; removeDeliveredNotifications must be true
        let presentation = StatusBarPresenter.presentation(
            nextEvent: nil,
            settings: presenterSettings(),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.mode, .noUpcoming)
        XCTAssertEqual(presentation.title, "")
        XCTAssertTrue(presentation.removeDeliveredNotifications,
                      "noUpcoming mode should trigger removal of delivered notifications")
    }

    func testPresenterReturnsEmptyPresentationForAfterThresholdMode() {
        // event 60 min away, threshold 30 min → mode = .afterThreshold → guard fires
        var s = presenterSettings()
        s = StatusBarPresenterSettings(
            presentation: StatusBarPresentationSettings(
                hasSelectedCalendars: true,
                showEventMaxTimeUntilEventEnabled: true,
                showEventMaxTimeUntilEventThreshold: 30
            ),
            title: s.title,
            timeDisplay: s.timeDisplay,
            iconFormat: s.iconFormat,
            iconFormatAssetName: s.iconFormatAssetName,
            iconAssets: s.iconAssets,
            pendingDisplay: s.pendingDisplay,
            tentativeDisplay: s.tentativeDisplay,
            compactTitleLimit: s.compactTitleLimit
        )
        let farEvent = StatusBarEventPresentationInput(
            title: "Far meeting",
            startDate: now.addingTimeInterval(3600),   // 60 min away
            endDate: now.addingTimeInterval(5400),
            meetingService: .zoom,
            participation: .normal
        )
        let presentation = StatusBarPresenter.presentation(
            nextEvent: farEvent,
            settings: s,
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.mode, .afterThreshold)
        XCTAssertEqual(presentation.title, "")
        XCTAssertFalse(presentation.removeDeliveredNotifications)
    }

    // MARK: - titleStyle: tentative + underlined

    func testPresenterTentativeWithUnderlinedDisplayStyleIsUnderlined() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(participation: .tentative),
            settings: presenterSettings(tentativeDisplay: .underlined),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.titleStyle, .underlined)
    }

    // MARK: - titleLayout: titleFormat .none + timeDisplay .showUnderTitle

    func testPresenterTitleFormatNoneWithTimeUnderTitleUsesInlineNoTime() {
        // titleFormat == .none AND timeDisplay == .showUnderTitle
        // → titleLayout exits early via guard and returns .inline(showTime: false)
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(),
            settings: presenterSettings(titleFormat: .none, timeDisplay: .showUnderTitle),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.layout, .inline(showTime: false))
    }

    // MARK: - titleLayout: titleFormat .show + timeDisplay .hide

    func testPresenterShowTitleWithHideTimeUsesInlineNoTime() {
        // titleFormat != .none AND timeDisplay == .hide
        // → titleLayout switch case .hide: return .inline(showTime: false)
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(),
            settings: presenterSettings(titleFormat: .show, timeDisplay: .hide),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.layout, .inline(showTime: false))
    }
}
