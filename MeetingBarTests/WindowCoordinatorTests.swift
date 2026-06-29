//
//  WindowCoordinatorTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class WindowCoordinatorTests: XCTestCase {
    func testFullscreenScreenSelectionPrefersKeyThenMainWindowScreen() {
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: "key",
                mainWindowScreen: "main-window",
                mouseScreen: "mouse",
                mainScreen: "main",
                screens: ["first"]
            ),
            "key"
        )
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: nil,
                mainWindowScreen: "main-window",
                mouseScreen: "mouse",
                mainScreen: "main",
                screens: ["first"]
            ),
            "main-window"
        )
    }

    func testFullscreenScreenSelectionUsesMouseScreenFallback() {
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: nil,
                mainWindowScreen: nil,
                mouseScreen: "mouse",
                mainScreen: "main",
                screens: ["first"]
            ),
            "mouse"
        )
    }

    func testFullscreenScreenSelectionUsesMainThenFirstScreenFallback() {
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: nil,
                mainWindowScreen: nil,
                mouseScreen: nil,
                mainScreen: "main",
                screens: ["first"]
            ),
            "main"
        )
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: nil,
                mainWindowScreen: nil,
                mouseScreen: nil,
                mainScreen: nil,
                screens: ["first"]
            ),
            "first"
        )
    }

    func testFullscreenKeyboardPolicyDismissesOnlyForEscape() {
        XCTAssertTrue(
            FullscreenNotificationKeyboardPolicy.shouldDismiss(
                keyCode: FullscreenNotificationKeyboardPolicy.escapeKeyCode
            )
        )
        XCTAssertFalse(FullscreenNotificationKeyboardPolicy.shouldDismiss(keyCode: 36))
    }

    func testFullscreenPresentationShowsJoinForJoinableEvent() {
        let event = makeFakeEvent(
            id: "joinable",
            start: Date(),
            end: Date().addingTimeInterval(1800),
            withLink: true
        )

        XCTAssertEqual(
            FullscreenNotificationPresentation.make(for: event).actions,
            [.dismiss, .join]
        )
    }

    func testFullscreenPresentationShowsDismissOnlyForNoLinkEvent() {
        let event = makeFakeEvent(
            id: "no-link",
            start: Date(),
            end: Date().addingTimeInterval(1800),
            withLink: false,
            calendarOpenURL: URL(string: "ical://ekevent/no-link")
        )

        XCTAssertEqual(
            FullscreenNotificationPresentation.make(for: event).actions,
            [.dismiss]
        )
    }

    func testOnboardingCloseRunsIncompleteOnboardingClosureOnlyWhenNotCompleted() {
        let coordinator = WindowCoordinator()
        var incompleteCloseCount = 0
        var changelogCloseCount = 0

        coordinator.handleWindowClosed(
            title: WindowTitles.onboarding,
            onboardingCompleted: false,
            onIncompleteOnboardingClosed: { incompleteCloseCount += 1 },
            onChangelogClosed: { changelogCloseCount += 1 }
        )

        XCTAssertEqual(incompleteCloseCount, 1)
        XCTAssertEqual(changelogCloseCount, 0)

        coordinator.handleWindowClosed(
            title: WindowTitles.onboarding,
            onboardingCompleted: true,
            onIncompleteOnboardingClosed: { incompleteCloseCount += 1 },
            onChangelogClosed: { changelogCloseCount += 1 }
        )

        XCTAssertEqual(incompleteCloseCount, 1)
        XCTAssertEqual(changelogCloseCount, 0)
    }

    func testChangelogCloseRunsChangelogClosure() {
        let coordinator = WindowCoordinator()
        var incompleteCloseCount = 0
        var changelogCloseCount = 0

        coordinator.handleWindowClosed(
            title: WindowTitles.changelog,
            onboardingCompleted: false,
            onIncompleteOnboardingClosed: { incompleteCloseCount += 1 },
            onChangelogClosed: { changelogCloseCount += 1 }
        )

        XCTAssertEqual(incompleteCloseCount, 0)
        XCTAssertEqual(changelogCloseCount, 1)
    }

    /// When the monitor an alert was shown on is disconnected, repositioning
    /// recomputes the target screen with the same policy used at open time.
    /// The disconnected screen is no longer among `screens`, so selection falls
    /// back to a still-connected one rather than the vanished display.
    func testFullscreenScreenSelectionFallsBackWhenScreenDisconnected() {
        // The external monitor that was the key window's screen is now gone;
        // only the built-in screen remains connected.
        let selected = FullscreenNotificationScreenSelectionPolicy.select(
            keyWindowScreen: String?.none,
            mainWindowScreen: String?.none,
            mouseScreen: String?.none,
            mainScreen: "built-in",
            screens: ["built-in"]
        )

        XCTAssertEqual(selected, "built-in")
    }
}
