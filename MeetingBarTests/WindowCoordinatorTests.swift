//
//  WindowCoordinatorTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class WindowCoordinatorTests: XCTestCase {
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
}
