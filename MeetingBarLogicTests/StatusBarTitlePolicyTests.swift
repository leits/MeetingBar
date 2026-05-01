//
//  StatusBarTitlePolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class StatusBarTitlePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func settings(
        titleFormat: StatusBarEventTitleFormat = .show,
        hideMeetingTitle: Bool = false,
        titleLength: Int = 55
    ) -> StatusBarTitleSettings {
        StatusBarTitleSettings(
            titleFormat: titleFormat,
            hideMeetingTitle: hideMeetingTitle,
            titleLength: titleLength,
            labels: StatusBarTitleLabels(
                genericMeetingTitle: "Meeting",
                noTitle: "No title",
                activeEventTimeFormat: "now (%@ left)",
                upcomingEventTimeFormat: "in %@"
            )
        )
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func text(
        title: String? = "Weekly sync",
        startOffset: TimeInterval = 600,
        endOffset: TimeInterval = 2400,
        settings: StatusBarTitleSettings? = nil
    ) -> StatusBarTitleText {
        StatusBarTitlePolicy.text(
            eventTitle: title,
            startDate: now.addingTimeInterval(startOffset),
            endDate: now.addingTimeInterval(endOffset),
            settings: settings ?? self.settings(),
            now: now,
            calendar: calendar()
        )
    }

    func testShowTitleShortensAndReplacesNewlines() {
        let result = text(
            title: "  Very long\nmeeting title  ",
            settings: settings(titleLength: 11)
        )

        XCTAssertEqual(result.title, "Very long m...")
    }

    func testHiddenMeetingTitleUsesGenericLabel() {
        let result = text(settings: settings(hideMeetingTitle: true))

        XCTAssertEqual(result.title, "Meeting")
    }

    func testNilTitleUsesNoTitleLabel() {
        let result = text(title: nil)

        XCTAssertEqual(result.title, "No title")
    }

    func testDotTitleFormatUsesBullet() {
        let result = text(settings: settings(titleFormat: .dot))

        XCTAssertEqual(result.title, "•")
    }

    func testNoneTitleFormatUsesEmptyTitle() {
        let result = text(settings: settings(titleFormat: .none))

        XCTAssertEqual(result.title, "")
    }

    func testRTLTitleIsPreserved() {
        let result = text(title: "פגישת צוות")

        XCTAssertEqual(result.title, "פגישת צוות")
    }

    func testFutureEventUsesUpcomingTimeText() {
        let result = text(startOffset: 600, endOffset: 2400)

        XCTAssertFalse(result.isActiveEvent)
        XCTAssertTrue(result.time.hasPrefix("in "))
    }

    func testActiveEventUsesActiveTimeText() {
        let result = text(startOffset: -300, endOffset: 900)

        XCTAssertTrue(result.isActiveEvent)
        XCTAssertTrue(result.time.hasPrefix("now ("))
        XCTAssertTrue(result.time.hasSuffix(" left)"))
    }
}
