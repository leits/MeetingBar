//
//  OnboardingFlowTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testSuccessfulAuthorizationAdvancesWithoutErrorState() {
        XCTAssertNil(OnboardingFlowPolicy.authorizationState(for: .success))
    }

    func testCancelledAuthorizationReturnsRetryableErrorState() {
        XCTAssertEqual(
            OnboardingFlowPolicy.authorizationState(for: .cancelled),
            .failed("access_screen_provider_authorization_cancelled".loco())
        )
    }

    func testAuthRequiredAndFailurePreserveTheirMessages() {
        XCTAssertEqual(
            OnboardingFlowPolicy.authorizationState(for: .authRequired("Reconnect")),
            .failed("Reconnect")
        )
        XCTAssertEqual(
            OnboardingFlowPolicy.authorizationState(for: .failed("Network failed")),
            .failed("Network failed")
        )
    }

    func testCalendarSelectionRequiresAtLeastOneCalendar() {
        XCTAssertFalse(
            OnboardingFlowPolicy.canContinueCalendarSelection(selectedCalendarIDs: [])
        )
        XCTAssertTrue(
            OnboardingFlowPolicy.canContinueCalendarSelection(
                selectedCalendarIDs: ["calendar"]
            )
        )
    }

    func testSelectingProviderMovesRouterToAuthorizationStep() {
        let router = OnboardingRouter()

        router.selectProvider(.googleCalendar)

        XCTAssertEqual(router.selectedProvider, .googleCalendar)
        XCTAssertEqual(router.authorizationState, .idle)
        XCTAssertEqual(router.currentStep, .authorization)
    }
}
