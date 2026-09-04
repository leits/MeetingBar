//
//  GoogleCalendarPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class GoogleCalendarPolicyTests: XCTestCase {
    private let calendarListURL = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
    private let calendarEventsURL = URL(string: "https://www.googleapis.com/calendar/v3/calendars/work/events")!

    func testHTTP2xxProceeds() {
        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 204,
            url: calendarListURL,
            calendarID: nil,
            retrying: false
        )

        XCTAssertEqual(decision, .proceed)
    }

    func testHTTP401BeforeRetryForcesTokenRefresh() {
        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 401,
            url: calendarListURL,
            calendarID: nil,
            retrying: false
        )

        XCTAssertEqual(decision, .retryWithForcedTokenRefresh)
    }

    func testHTTP403BeforeRetryForcesTokenRefresh() {
        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 403,
            url: calendarEventsURL,
            calendarID: "work",
            retrying: false
        )

        XCTAssertEqual(decision, .retryWithForcedTokenRefresh)
    }

    func testHTTP403AfterRetryWithoutCalendarIDIsForbiddenNotAuthRequired() {
        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 403,
            url: calendarListURL,
            calendarID: nil,
            retrying: true
        )

        XCTAssertEqual(
            decision,
            .throwError(.forbiddenCalendar(calendarID: nil, url: calendarListURL))
        )
    }

    /// A 401 from the Calendar API proves only that this access token was
    /// refused. Discarding the stored session here turned a proxy or captive
    /// portal into a forced re-consent, so the decision must stay "ask the user
    /// to reconnect" and leave the refresh token alone.
    func testHTTP401AfterRetryAsksForAuthWithoutClearingSession() {
        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 401,
            url: calendarListURL,
            calendarID: nil,
            retrying: true
        )

        XCTAssertEqual(decision, .throwAuthRequired)
    }

    func testHTTP403AfterRetryWithCalendarIDIsForbiddenCalendar() {
        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 403,
            url: calendarEventsURL,
            calendarID: "work",
            retrying: true
        )

        XCTAssertEqual(
            decision,
            .throwError(.forbiddenCalendar(calendarID: "work", url: calendarEventsURL))
        )
    }

    func testHTTP500ThrowsStatusError() {
        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 500,
            url: calendarListURL,
            calendarID: nil,
            retrying: false
        )

        XCTAssertEqual(
            decision,
            .throwError(.httpStatus(500, url: calendarListURL))
        )
    }

    func testNoSelectedCalendarsReturnsEmptyWithoutFailure() throws {
        let events: [String] = try GoogleCalendarBatchPolicy.finish(
            events: [],
            successfulCalendars: 0,
            forbiddenErrors: []
        )

        XCTAssertEqual(events, [])
    }

    func testSuccessfulEmptyCalendarWithForbiddenCalendarReturnsEmptyWithoutFailure() throws {
        let forbidden = GoogleCalendarError.forbiddenCalendar(calendarID: "work", url: calendarEventsURL)

        let events: [String] = try GoogleCalendarBatchPolicy.finish(
            events: [],
            successfulCalendars: 1,
            forbiddenErrors: [forbidden]
        )

        XCTAssertEqual(events, [])
    }

    func testSuccessfulCalendarWithEventsIgnoresForbiddenCalendarErrors() throws {
        let event = "ok"
        let forbidden = GoogleCalendarError.forbiddenCalendar(calendarID: "work", url: calendarEventsURL)

        let events = try GoogleCalendarBatchPolicy.finish(
            events: [event],
            successfulCalendars: 1,
            forbiddenErrors: [forbidden]
        )

        XCTAssertEqual(events, [event])
    }

    func testAllForbiddenCalendarsThrowsRepresentativeError() {
        let forbidden = GoogleCalendarError.forbiddenCalendar(calendarID: "work", url: calendarEventsURL)

        XCTAssertThrowsError(
            try GoogleCalendarBatchPolicy.finish(
                events: [],
                successfulCalendars: 0,
                forbiddenErrors: [forbidden]
            ) as [String]
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarError, forbidden)
        }
    }

    func testAuthErrorDescriptionsExplainRequiredAction() {
        XCTAssertEqual(AuthError.notSignedIn.errorDescription, "Google Calendar authorization is required")
        XCTAssertEqual(AuthError.refreshFailed.errorDescription, "Google Calendar token refresh failed")
    }

    func testTemporarilyUnavailableDescriptionNamesTheUnderlyingFailure() {
        let underlying = URLError(.notConnectedToInternet)

        XCTAssertEqual(
            AuthError.temporarilyUnavailable(underlying: underlying).errorDescription,
            "Google Calendar is temporarily unreachable: \(underlying.localizedDescription)"
        )
    }

    func testGoogleCalendarErrorDescriptionsIncludeUsefulContext() {
        XCTAssertEqual(
            GoogleCalendarError.unauthorized(calendarListURL).errorDescription,
            "Google Calendar authorization failed: \(calendarListURL.absoluteString)"
        )
        XCTAssertEqual(
            GoogleCalendarError.forbiddenCalendar(calendarID: "work", url: calendarEventsURL).errorDescription,
            "Google Calendar is not accessible: work"
        )
        XCTAssertEqual(
            GoogleCalendarError.forbiddenCalendar(calendarID: nil, url: calendarListURL).errorDescription,
            "Google Calendar access is forbidden: \(calendarListURL.absoluteString)"
        )
        XCTAssertEqual(
            GoogleCalendarError.httpStatus(500, url: calendarEventsURL).errorDescription,
            "Google Calendar request failed with HTTP 500: \(calendarEventsURL.absoluteString)"
        )
        XCTAssertEqual(
            GoogleCalendarError.missingItems(calendarListURL).errorDescription,
            "Google Calendar response did not contain an items array: \(calendarListURL.absoluteString)"
        )
    }
}

final class SingleResumeGuardTests: XCTestCase {
    func testFirstClaimSucceedsAndEveryLaterClaimFails() {
        let guardBox = SingleResumeGuard()

        XCTAssertTrue(guardBox.claim())
        XCTAssertFalse(guardBox.claim())
        XCTAssertFalse(guardBox.claim())
    }

    /// The guard exists to arbitrate a token-refresh completion racing its
    /// timeout, and those two callbacks are not guaranteed to share a queue.
    /// Exactly one contender may ever resume the continuation.
    func testExactlyOneClaimWinsUnderConcurrentContention() {
        let contenders = 500
        let guardBox = SingleResumeGuard()
        let winners = NSCountedSet()
        let winnersLock = NSLock()

        DispatchQueue.concurrentPerform(iterations: contenders) { _ in
            guard guardBox.claim() else { return }
            winnersLock.lock()
            winners.add("won")
            winnersLock.unlock()
        }

        XCTAssertEqual(winners.count(for: "won"), 1)
    }
}
