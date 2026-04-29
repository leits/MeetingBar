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
}
