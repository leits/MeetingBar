//
//  StatusBarIconPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class StatusBarIconPolicyTests: XCTestCase {
    private let assets = StatusBarIconAssets(
        appIcon: "AppIcon",
        calendarCheckmark: "iconCalendarCheckmark",
        calendar: "iconCalendar"
    )

    private func icon(
        mode: StatusBarTitleMode,
        format: StatusBarIconFormat,
        formatAssetName: String? = nil,
        meetingService: MeetingServices? = nil
    ) -> StatusBarIcon {
        StatusBarIconPolicy.icon(
            mode: mode,
            format: format,
            formatAssetName: formatAssetName ?? rawAssetName(for: format),
            meetingService: meetingService,
            assets: assets
        )
    }

    private func rawAssetName(for format: StatusBarIconFormat) -> String {
        switch format {
        case .calendar: return "iconCalendar"
        case .appicon: return "AppIcon"
        case .eventtype: return "ms_teams_icon"
        case .none: return "no_online_session"
        }
    }

    // MARK: - idle

    func testIdleAlwaysReturnsAppIcon() {
        let formats: [StatusBarIconFormat] = [.calendar, .appicon, .eventtype, .none]
        for format in formats {
            XCTAssertEqual(
                icon(mode: .idle, format: format),
                .asset(assets.appIcon),
                "format \(format) under .idle should still produce app icon"
            )
        }
    }

    // MARK: - noUpcoming

    func testNoUpcomingAppIconFormatReturnsAppIcon() {
        XCTAssertEqual(icon(mode: .noUpcoming, format: .appicon), .asset(assets.appIcon))
    }

    func testNoUpcomingNonAppIconFormatsReturnCalendarCheckmark() {
        XCTAssertEqual(icon(mode: .noUpcoming, format: .calendar), .asset(assets.calendarCheckmark))
        XCTAssertEqual(icon(mode: .noUpcoming, format: .eventtype), .asset(assets.calendarCheckmark))
        XCTAssertEqual(icon(mode: .noUpcoming, format: .none), .asset(assets.calendarCheckmark))
    }

    // MARK: - afterThreshold

    func testAfterThresholdAppIconFormatReturnsAppIcon() {
        XCTAssertEqual(icon(mode: .afterThreshold, format: .appicon), .asset(assets.appIcon))
    }

    func testAfterThresholdNonAppIconFormatsReturnCalendar() {
        XCTAssertEqual(icon(mode: .afterThreshold, format: .calendar), .asset(assets.calendar))
        XCTAssertEqual(icon(mode: .afterThreshold, format: .eventtype), .asset(assets.calendar))
        XCTAssertEqual(icon(mode: .afterThreshold, format: .none), .asset(assets.calendar))
    }

    // MARK: - nextEvent

    func testNextEventNoneFormatReturnsNoIcon() {
        XCTAssertEqual(icon(mode: .nextEvent, format: .none), .none)
    }

    func testNextEventEventTypeReturnsMeetingService() {
        XCTAssertEqual(
            icon(mode: .nextEvent, format: .eventtype, meetingService: .zoom),
            .meetingService(.zoom)
        )
    }

    func testNextEventEventTypeWithoutMeetingServicePassesNil() {
        XCTAssertEqual(
            icon(mode: .nextEvent, format: .eventtype, meetingService: nil),
            .meetingService(nil)
        )
    }

    func testNextEventAppIconFormatReturnsAppIconAsset() {
        XCTAssertEqual(
            icon(mode: .nextEvent, format: .appicon),
            .asset("AppIcon")
        )
    }

    func testNextEventCalendarFormatReturnsCalendarAsset() {
        XCTAssertEqual(
            icon(mode: .nextEvent, format: .calendar),
            .asset("iconCalendar")
        )
    }

    // MARK: - boundary cases

    func testFormatAssetNameOverridesAssetsForCustomFormat() {
        // Even if a future build adds new EventTitleIconFormat cases, the
        // policy passes the format's rawValue through transparently for
        // .appicon / .calendar so user-visible behavior matches the asset
        // pinned to the Defaults enum, not the StatusBarIconAssets table.
        let custom = icon(
            mode: .nextEvent,
            format: .calendar,
            formatAssetName: "future_calendar_icon"
        )
        XCTAssertEqual(custom, .asset("future_calendar_icon"))
    }
}
