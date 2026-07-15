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

    func testOnboardingWindowPolicyAllowsNormalMovableResizableWindow() {
        XCTAssertEqual(OnboardingWindowPresentationPolicy.level, .normal)
        XCTAssertTrue(OnboardingWindowPresentationPolicy.styleMask.contains(.resizable))
        XCTAssertTrue(OnboardingWindowPresentationPolicy.isMovableByWindowBackground)
        XCTAssertLessThan(
            OnboardingWindowPresentationPolicy.minimumSize.width,
            OnboardingWindowPresentationPolicy.contentRect.width
        )
        XCTAssertLessThan(
            OnboardingWindowPresentationPolicy.minimumSize.height,
            OnboardingWindowPresentationPolicy.contentRect.height
        )
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

    /// An external monitor an alert was shown on is disconnected: its frame no
    /// longer intersects any connected screen, so the alert must be moved.
    func testRepositionNeededWhenAlertScreenDisconnected() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Alert is sitting on a second display to the right that is now gone.
        let alertOnExternal = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        XCTAssertTrue(
            FullscreenNotificationRepositionPolicy.needsReposition(
                windowFrame: alertOnExternal,
                screenFrames: [builtIn]
            )
        )
    }

    /// The alert is still fully within a connected screen, so a display change
    /// elsewhere must not yank it to another screen.
    func testRepositionNotNeededWhenAlertStillOnConnectedScreen() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        XCTAssertFalse(
            FullscreenNotificationRepositionPolicy.needsReposition(
                windowFrame: builtIn,
                screenFrames: [builtIn, external]
            )
        )
    }

    /// A partially off-screen alert (overlapping a connected screen but not
    /// fully contained) is still considered stranded and is repositioned.
    func testRepositionNeededWhenAlertOnlyPartiallyOnScreen() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let halfOff = CGRect(x: 1000, y: 0, width: 1440, height: 900)

        XCTAssertTrue(
            FullscreenNotificationRepositionPolicy.needsReposition(
                windowFrame: halfOff,
                screenFrames: [builtIn]
            )
        )
    }
}
