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

    func testHTTP401AfterRetryClearsAuthAndThrowsAuthRequired() {
        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 401,
            url: calendarListURL,
            calendarID: nil,
            retrying: true
        )

        XCTAssertEqual(decision, .clearAuthAndThrowAuthRequired)
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
