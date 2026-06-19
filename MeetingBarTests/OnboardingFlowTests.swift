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
            OnboardingFlowPolicy.canContinueCalendarSelection(
                selectedCalendarIDs: [],
                availableCalendarIDs: ["calendar"]
            )
        )
        XCTAssertTrue(
            OnboardingFlowPolicy.canContinueCalendarSelection(
                selectedCalendarIDs: ["calendar"],
                availableCalendarIDs: ["calendar"]
            )
        )
    }

    func testCalendarSelectionRejectsStaleSelectionFromAnotherProvider() {
        XCTAssertFalse(
            OnboardingFlowPolicy.canContinueCalendarSelection(
                selectedCalendarIDs: ["previous-provider-calendar"],
                availableCalendarIDs: ["active-provider-calendar"]
            )
        )
    }

    func testProgressMapsStepsToFourUserFacingStages() {
        XCTAssertEqual(OnboardingProgressPolicy.totalStages, 4)
        XCTAssertEqual(OnboardingProgressPolicy.stageIndex(for: .welcome), 1)
        // Authorization runs automatically as part of source selection, so it
        // shares the source stage rather than counting as its own.
        XCTAssertEqual(OnboardingProgressPolicy.stageIndex(for: .calendarSource), 2)
        XCTAssertEqual(OnboardingProgressPolicy.stageIndex(for: .authorization), 2)
        XCTAssertEqual(OnboardingProgressPolicy.stageIndex(for: .calendarSelection), 3)
        XCTAssertEqual(OnboardingProgressPolicy.stageIndex(for: .essentials), 4)
        // The terminal success screen shows no progress position.
        XCTAssertNil(OnboardingProgressPolicy.stageIndex(for: .success))
    }

    func testSelectingProviderMovesRouterToAuthorizationStep() {
        let router = OnboardingRouter()

        router.selectProvider(.googleCalendar)

        XCTAssertEqual(router.selectedProvider, .googleCalendar)
        XCTAssertEqual(router.authorizationState, .idle)
        XCTAssertEqual(router.currentStep, .authorization)
    }

    func testSuccessfulProviderSelectionEntersCalendarSelectionWithCalendars() async {
        let harness = AppModelTestHarness()
        let calendar = makeFakeCalendar(id: "google-calendar")
        harness.providerCalendarsAfterChange = [calendar]
        let router = OnboardingRouter()
        router.selectProvider(.googleCalendar)

        let result = await harness.model.changeProvider(to: .googleCalendar)
        if result == .success {
            router.currentStep = .calendarSelection
        }

        XCTAssertEqual(result, .success)
        XCTAssertEqual(router.currentStep, .calendarSelection)
        XCTAssertEqual(harness.model.state.calendars, [calendar])
    }
}
