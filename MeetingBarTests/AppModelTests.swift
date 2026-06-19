//
//  AppModelTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class AppModelTests: BaseTestCase {
    func testLaunchTriggersRefresh() async {
        let harness = AppModelTestHarness()

        harness.model.send(.launched)
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.refreshCallCount, 1)
    }

    func testSystemClockChangeRefreshesTimeDerivedStateAndNotifications() async {
        let harness = AppModelTestHarness()
        let event = makeFakeEvent(
            id: "clock-change",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1800)
        )
        harness.model.send(.eventsLoaded([event]))
        await harness.flushAsyncActions()

        harness.model.send(.systemClockChanged)
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.timeContextRevision, 1)
        XCTAssertEqual(harness.refreshCallCount, 1)
        XCTAssertEqual(harness.reconciledEventIDs, [
            [event.id],
            [event.id]
        ])
    }

    func testTimezoneChangeRefreshesTimeDerivedStateAndNotifications() async {
        let harness = AppModelTestHarness()
        let event = makeFakeEvent(
            id: "timezone-change",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1800)
        )
        harness.model.send(.eventsLoaded([event]))
        await harness.flushAsyncActions()

        harness.model.send(.timezoneChanged)
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.timeContextRevision, 1)
        XCTAssertEqual(harness.refreshCallCount, 1)
        XCTAssertEqual(harness.reconciledEventIDs.last, [event.id])
    }

    func testLifecycleObserverForwardsSystemClockChanges() async {
        let observer = LifecycleObserver()
        let callback = expectation(description: "system clock callback")
        observer.onSystemClockChanged = {
            callback.fulfill()
        }
        observer.start()
        defer { observer.stop() }

        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)

        await fulfillment(of: [callback], timeout: 1)
    }

    func testProviderChangeClearsStateAndDelegatesToEnvironment() async {
        let harness = AppModelTestHarness()
        let calendar = makeFakeCalendar(id: "cal")
        let event = makeFakeEvent(
            id: "event",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1800)
        )
        harness.model.send(.calendarsLoaded([calendar], provider: .macOSEventKit))
        harness.model.send(.eventsLoaded([event]))

        harness.model.send(.changeProvider(.googleCalendar, signOut: true))
        XCTAssertTrue(harness.model.state.providerChangeInProgress)
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.activeProvider, .googleCalendar)
        XCTAssertFalse(harness.model.state.providerChangeInProgress)
        XCTAssertTrue(harness.model.state.calendars.isEmpty)
        XCTAssertTrue(harness.model.state.events.isEmpty)
        XCTAssertEqual(harness.providerChanges.map(\.provider), [.googleCalendar])
        XCTAssertEqual(harness.providerChanges.map(\.signOut), [true])
    }

    func testSuccessfulProviderChangeUsesAlreadyFetchedCalendars() async {
        let harness = AppModelTestHarness()
        let googleCalendar = makeFakeCalendar(id: "google-calendar")
        harness.providerCalendarsAfterChange = [googleCalendar]

        let result = await harness.model.changeProvider(to: .googleCalendar)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(harness.model.state.activeProvider, .googleCalendar)
        XCTAssertEqual(harness.model.state.calendars, [googleCalendar])
        XCTAssertFalse(harness.model.state.providerChangeInProgress)
    }

    func testFailedProviderChangePreservesCurrentState() async {
        let harness = AppModelTestHarness()
        harness.providerSelectionResult = .cancelled
        let calendar = makeFakeCalendar(id: "cal")
        let event = makeFakeEvent(
            id: "event",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1800)
        )
        harness.model.send(.calendarsLoaded([calendar], provider: .macOSEventKit))
        harness.model.send(.eventsLoaded([event]))

        harness.model.send(.changeProvider(.googleCalendar, signOut: false))
        XCTAssertTrue(harness.model.state.providerChangeInProgress)
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.activeProvider, .macOSEventKit)
        XCTAssertFalse(harness.model.state.providerChangeInProgress)
        XCTAssertEqual(harness.model.state.calendars, [calendar])
        XCTAssertEqual(harness.model.state.events, [event])
    }

    func testCancelledOnboardingPreservesCurrentState() async {
        let harness = AppModelTestHarness()
        harness.providerSelectionResult = .cancelled
        let calendar = makeFakeCalendar(id: "cal")
        harness.model.send(.calendarsLoaded([calendar], provider: .macOSEventKit))
        harness.publishSelectedCalendarIDs([calendar.id])

        let result = await harness.model.completeOnboarding(with: .googleCalendar)

        XCTAssertEqual(result, .failed("The selected calendar provider is not active"))
        XCTAssertEqual(harness.model.state.activeProvider, .macOSEventKit)
        XCTAssertEqual(harness.model.state.calendars, [calendar])
        XCTAssertTrue(harness.completedOnboardingProviders.isEmpty)
    }

    func testOnboardingCompletionRequiresSelectedCalendar() async {
        let harness = AppModelTestHarness()
        harness.model.send(.calendarsLoaded([], provider: .googleCalendar))

        let result = await harness.model.completeOnboarding(with: .googleCalendar)

        XCTAssertEqual(result, .failed("Select at least one calendar"))
        XCTAssertTrue(harness.completedOnboardingProviders.isEmpty)
    }

    func testOnboardingCompletionSucceedsAfterProviderAndCalendarSelection() async {
        let harness = AppModelTestHarness()
        harness.model.send(.calendarsLoaded([], provider: .googleCalendar))
        harness.publishSelectedCalendarIDs(["google-calendar"])
        await harness.flushAsyncActions()

        let result = await harness.model.completeOnboarding(with: .googleCalendar)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(harness.completedOnboardingProviders, [.googleCalendar])
    }

    func testCancelledOnboardingProviderSelectionDoesNotComplete() async {
        let harness = AppModelTestHarness()
        harness.providerSelectionResult = .cancelled

        let result = await harness.model.changeProvider(to: .googleCalendar)

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(harness.model.state.activeProvider, .macOSEventKit)
        XCTAssertTrue(harness.completedOnboardingProviders.isEmpty)
    }

    func testCalendarSelectionDelegatesToEnvironment() {
        let harness = AppModelTestHarness()

        harness.model.send(.selectCalendar(id: "cal", selected: true))
        harness.model.toggleCalendarSelection(id: "cal", selected: false)

        XCTAssertEqual(harness.calendarSelections.map(\.id), ["cal", "cal"])
        XCTAssertEqual(harness.calendarSelections.map(\.selected), [true, false])
    }

    func testSelectedCalendarChangesUpdateState() async {
        let harness = AppModelTestHarness()
        _ = harness.model

        harness.publishSelectedCalendarIDs(["calendar-a", "calendar-b"])
        await harness.flushAsyncActions()

        XCTAssertEqual(
            harness.model.state.selectedCalendarIDs,
            ["calendar-a", "calendar-b"]
        )
    }

    func testEventsLoadedUpdatesStateAndReconcilesNotifications() async {
        let harness = AppModelTestHarness()
        let event = makeFakeEvent(
            id: "event",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1800)
        )

        harness.model.send(.eventsLoaded([event]))
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.events.map(\.id), ["event"])
        XCTAssertEqual(harness.reconciledEventIDs, [["event"]])
    }

    func testProviderHealthUpdatesState() async {
        let harness = AppModelTestHarness()
        _ = harness.model
        let health = ProviderHealth(
            lastSuccessfulRefresh: harness.fixedNow,
            lastAttemptedRefresh: harness.fixedNow,
            lastErrorDescription: "Refresh failed",
            isStale: true,
            authRequired: true
        )

        harness.publishProviderHealth(health)
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.providerHealth, health)
    }

    func testNearestEventUsesInjectedClock() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let harness = AppModelTestHarness(now: now)
        let endedEvent = makeFakeEvent(
            id: "ended",
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(-1800)
        )
        let nextEvent = makeFakeEvent(
            id: "next",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(1800)
        )

        harness.model.send(.eventsLoaded([endedEvent, nextEvent]))

        XCTAssertEqual(harness.model.nextEvent()?.id, "next")
    }

    func testJoinDismissAndSnoozeActionsUseEventsFromState() async {
        let harness = AppModelTestHarness()
        let event = makeFakeEvent(
            id: "event",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1800)
        )
        harness.model.send(.eventsLoaded([event]))

        harness.model.send(.joinMeeting(eventID: "event"))
        harness.model.send(.dismissMeeting(eventID: "event"))
        harness.model.send(.undismissMeeting(eventID: "event"))
        harness.model.send(.clearDismissedMeetings)
        harness.model.send(.snoozeMeeting(eventID: "event", action: .tenMinuteLater))
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.openedMeetingIDs, ["event"])
        XCTAssertEqual(harness.dismissedEventIDs, ["event"])
        XCTAssertEqual(harness.undismissedEventIDs, ["event"])
        XCTAssertEqual(harness.clearDismissedEventsCallCount, 1)
        XCTAssertEqual(harness.snoozedEvents.map(\.id), ["event"])
        XCTAssertEqual(harness.snoozedEvents.map(\.action.rawValue), [
            NotificationEventTimeAction.tenMinuteLater.rawValue
        ])
    }

    func testNotificationResponsesRouteThroughMeetingActions() async {
        let harness = AppModelTestHarness()
        let event = makeFakeEvent(
            id: "notification-event",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1800)
        )
        harness.model.send(.eventsLoaded([event]))

        harness.model.send(.notificationResponse(.join(eventID: event.id)))
        harness.model.send(.notificationResponse(.dismiss(eventID: event.id)))
        harness.model.send(.notificationResponse(
            .snooze(eventID: event.id, action: .fifteenMinuteLater)
        ))
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.openedMeetingIDs, [event.id])
        XCTAssertEqual(harness.dismissedEventIDs, [event.id])
        XCTAssertEqual(harness.snoozedEvents.map(\.id), [event.id])
        XCTAssertEqual(harness.snoozedEvents.map(\.action), [.fifteenMinuteLater])
    }

    func testNearestJoinAndDismissUseInjectedClock() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let harness = AppModelTestHarness(now: now)
        let event = makeFakeEvent(
            id: "next",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(1800)
        )
        harness.model.send(.eventsLoaded([event]))

        harness.model.send(.joinNearestMeeting)
        harness.model.send(.dismissNearestMeeting)

        XCTAssertEqual(harness.openedMeetingIDs, ["next"])
        XCTAssertEqual(harness.dismissedEventIDs, ["next"])
    }

    func testJoinNearestPrefersOngoingMeetingOverFutureMeeting() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let harness = AppModelTestHarness(now: now)
        let ongoing = makeFakeEvent(
            id: "ongoing",
            start: now.addingTimeInterval(-300),
            end: now.addingTimeInterval(900),
            withLink: true
        )
        let future = makeFakeEvent(
            id: "future",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        harness.model.send(.eventsLoaded([future, ongoing]))

        harness.model.send(.joinNearestMeeting)

        XCTAssertEqual(harness.openedMeetingIDs, ["ongoing"])
    }

    func testToggleMeetingTitleVisibilityDelegatesToEnvironment() {
        let harness = AppModelTestHarness()

        harness.model.send(.toggleMeetingTitleVisibility)

        XCTAssertEqual(harness.toggleMeetingTitleVisibilityCallCount, 1)
    }

    func testOnboardingCompletionDelegatesProviderSelection() async {
        let harness = AppModelTestHarness()
        harness.model.send(.calendarsLoaded([], provider: .googleCalendar))
        harness.publishSelectedCalendarIDs(["google-calendar"])
        await harness.flushAsyncActions()

        harness.model.send(.onboardingCompleted(.googleCalendar))
        await harness.flushAsyncActions()

        XCTAssertEqual(harness.model.state.activeProvider, .googleCalendar)
        XCTAssertEqual(harness.completedOnboardingProviders, [.googleCalendar])
    }

    func testOpenRouteDelegatesToAppBoundaries() {
        let harness = AppModelTestHarness()
        let oauthURL = URL(string: "com.googleusercontent.apps.123:/oauthredirect?code=abc")!

        harness.model.send(.openRoute(.preferences))
        harness.model.send(.openRoute(.oauthCallback(oauthURL)))
        harness.model.send(.openRoute(.unknown(URL(string: "meetingbar://unknown")!)))

        XCTAssertEqual(harness.openPreferencesCallCount, 1)
        XCTAssertEqual(harness.resumedOAuthURLs, [oauthURL])
    }

    func testWillTerminateCancelsOwnedAsyncOperations() async {
        let harness = AppModelTestHarness(asyncOperationDelayNanoseconds: 1_000_000_000)
        let event = makeFakeEvent(
            id: "event",
            start: harness.fixedNow,
            end: harness.fixedNow.addingTimeInterval(1800)
        )
        harness.model.send(.calendarsLoaded([], provider: .googleCalendar))
        harness.publishSelectedCalendarIDs(["google-calendar"])
        await harness.flushAsyncActions()

        harness.model.send(.changeProvider(.googleCalendar, signOut: true))
        harness.model.send(.eventsLoaded([event]))
        harness.model.send(.snoozeMeeting(eventID: event.id, action: .tenMinuteLater))
        harness.model.send(.onboardingCompleted(.googleCalendar))
        let startDeadline = Date().addingTimeInterval(1)
        while harness.startedAsyncOperationCount < 4, Date() < startDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(harness.startedAsyncOperationCount, 4)

        harness.model.send(.willTerminate)
        let cancellationDeadline = Date().addingTimeInterval(1)
        while harness.cancelledAsyncOperationCount < 4, Date() < cancellationDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(harness.cancelledAsyncOperationCount, 4)
        XCTAssertTrue(harness.providerChanges.isEmpty)
        XCTAssertTrue(harness.reconciledEventIDs.isEmpty)
        XCTAssertTrue(harness.snoozedEvents.isEmpty)
        XCTAssertTrue(harness.completedOnboardingProviders.isEmpty)
    }
}
