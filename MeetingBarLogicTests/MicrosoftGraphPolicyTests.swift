//
//  MicrosoftGraphPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class MicrosoftGraphPolicyTests: XCTestCase {
    private let calendarsURL = URL(string: "https://graph.microsoft.com/v1.0/me/calendars")!
    private let calendarViewURL = URL(string: "https://graph.microsoft.com/v1.0/me/calendars/work/calendarView")!

    private func classify(
        _ statusCode: Int,
        url: URL? = nil,
        calendarID: String? = nil,
        graphErrorCode: String? = nil,
        retryAfterHeader: String? = nil,
        retrying: Bool = false,
        rateLimitRetries: Int = 0
    ) -> MicrosoftGraphHTTPDecision {
        MicrosoftGraphHTTPStatusPolicy.classify(
            MicrosoftGraphResponse(
                statusCode: statusCode,
                url: url ?? (calendarID == nil ? calendarsURL : calendarViewURL),
                calendarID: calendarID,
                graphErrorCode: graphErrorCode,
                retryAfterHeader: retryAfterHeader
            ),
            retrying: retrying,
            rateLimitRetries: rateLimitRetries
        )
    }

    // MARK: - HTTP status policy

    func testHTTP2xxProceeds() {
        XCTAssertEqual(classify(200), .proceed)
        XCTAssertEqual(classify(204), .proceed)
    }

    func testHTTP401BeforeRetryForcesTokenRefresh() {
        XCTAssertEqual(classify(401), .retryWithForcedTokenRefresh)
    }

    func testHTTP401AfterRetryClearsAuth() {
        XCTAssertEqual(classify(401, retrying: true), .clearAuthAndThrowAuthRequired)
    }

    func testHTTP403ForCalendarIsForbiddenWithoutTokenRetry() {
        XCTAssertEqual(
            classify(403, calendarID: "work"),
            .throwError(.forbiddenCalendar(calendarID: "work", url: calendarViewURL))
        )
    }

    func testHTTP403WithoutCalendarIsForbidden() {
        XCTAssertEqual(
            classify(403),
            .throwError(.forbiddenCalendar(calendarID: nil, url: calendarsURL))
        )
    }

    func testHTTP404ForCalendarIsForbidden() {
        XCTAssertEqual(
            classify(404, calendarID: "gone"),
            .throwError(.forbiddenCalendar(calendarID: "gone", url: calendarViewURL))
        )
    }

    func testHTTP404WithMailboxCodeIsMailboxNotAvailable() {
        XCTAssertEqual(
            classify(404, graphErrorCode: "MailboxNotEnabledForRESTAPI"),
            .throwError(.mailboxNotAvailable(calendarsURL))
        )
    }

    func testHTTP404WithoutMailboxCodeIsHTTPError() {
        XCTAssertEqual(
            classify(404, graphErrorCode: "SomethingElse"),
            .throwError(.httpStatus(404, code: "SomethingElse", url: calendarsURL))
        )
    }

    func testHTTP429FirstTimeRetriesAfterHeaderDelay() {
        XCTAssertEqual(classify(429, retryAfterHeader: "3"), .retryAfterDelay(3))
    }

    func testHTTP429SecondTimeThrowsRateLimited() {
        XCTAssertEqual(
            classify(429, retryAfterHeader: "3", rateLimitRetries: 1),
            .throwError(.rateLimited(retryAfter: 3, url: calendarsURL))
        )
    }

    func testHTTP503IsTreatedLikeThrottling() {
        XCTAssertEqual(classify(503), .retryAfterDelay(MicrosoftGraphHTTPStatusPolicy.defaultRetryAfter))
    }

    func testRetryAfterParsing() {
        XCTAssertEqual(MicrosoftGraphHTTPStatusPolicy.retryAfterInterval(header: "120"), 120)
        XCTAssertEqual(MicrosoftGraphHTTPStatusPolicy.retryAfterInterval(header: " 5 "), 5)
        XCTAssertNil(MicrosoftGraphHTTPStatusPolicy.retryAfterInterval(header: nil))
        XCTAssertNil(MicrosoftGraphHTTPStatusPolicy.retryAfterInterval(header: "garbage"))
        XCTAssertNil(MicrosoftGraphHTTPStatusPolicy.retryAfterInterval(header: "0"))
    }

    func testRetryAfterParsesHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_788_948_000)
        let future = "Wed, 09 Sep 2026 10:01:00 GMT" // 60s after `now`
        XCTAssertEqual(MicrosoftGraphHTTPStatusPolicy.retryAfterInterval(header: future, now: now), 60)
        let past = "Wed, 09 Sep 2026 09:59:00 GMT"
        XCTAssertNil(MicrosoftGraphHTTPStatusPolicy.retryAfterInterval(header: past, now: now))
    }

    func testLargeRetryAfterIsDeferredNotRetriedInline() {
        // A long delay is thrown as rateLimited (handled by the next sync)
        // rather than retried early.
        XCTAssertEqual(
            classify(429, retryAfterHeader: "120"),
            .throwError(.rateLimited(retryAfter: 120, url: calendarsURL))
        )
    }

    func testHTTP500IsHTTPError() {
        XCTAssertEqual(
            classify(500, graphErrorCode: "InternalServerError"),
            .throwError(.httpStatus(500, code: "InternalServerError", url: calendarsURL))
        )
    }

    // MARK: - Batch policy

    func testBatchReturnsEventsWhenAnyCalendarSucceeded() throws {
        let events = try MicrosoftGraphBatchPolicy.finish(
            events: ["a", "b"],
            successfulCalendars: 1,
            forbiddenErrors: [MicrosoftGraphError.forbiddenCalendar(calendarID: "x", url: calendarViewURL)]
        )
        XCTAssertEqual(events, ["a", "b"])
    }

    func testBatchThrowsFirstErrorWhenEveryCalendarFailed() {
        let forbidden = MicrosoftGraphError.forbiddenCalendar(calendarID: "x", url: calendarViewURL)
        XCTAssertThrowsError(
            try MicrosoftGraphBatchPolicy.finish(events: [String](), successfulCalendars: 0, forbiddenErrors: [forbidden])
        ) { error in
            XCTAssertEqual(error as? MicrosoftGraphError, forbidden)
        }
    }

    func testBatchWithNoCalendarsAndNoErrorsReturnsEmpty() throws {
        let events: [String] = try MicrosoftGraphBatchPolicy.finish(events: [], successfulCalendars: 0, forbiddenErrors: [])
        XCTAssertEqual(events, [])
    }

    // MARK: - Date parsing

    func testParsesGraphSevenDigitFractionAsUTC() {
        let date = MicrosoftGraphDateParser.dateTime("2026-09-09T10:00:00.0000000", timeZoneID: "UTC")
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1_788_948_000))
    }

    func testParsesFractionAndNoFraction() {
        let base = MicrosoftGraphDateParser.dateTime("2026-09-09T10:00:00", timeZoneID: "UTC")
        let fraction = MicrosoftGraphDateParser.dateTime("2026-09-09T10:00:00.5", timeZoneID: "UTC")
        XCTAssertEqual(base, Date(timeIntervalSince1970: 1_788_948_000))
        XCTAssertEqual(fraction, Date(timeIntervalSince1970: 1_788_948_000.5))
    }

    func testParsesExplicitDesignatorsOverTimeZoneField() {
        let zulu = MicrosoftGraphDateParser.dateTime("2026-09-09T10:00:00Z", timeZoneID: "Asia/Tokyo")
        let offset = MicrosoftGraphDateParser.dateTime("2026-09-09T19:00:00+09:00", timeZoneID: nil)
        XCTAssertEqual(zulu, Date(timeIntervalSince1970: 1_788_948_000))
        XCTAssertEqual(offset, Date(timeIntervalSince1970: 1_788_948_000))
    }

    func testUsesTimeZoneFieldWhenNoDesignator() {
        let tokyo = MicrosoftGraphDateParser.dateTime("2026-09-09T19:00:00.0000000", timeZoneID: "Asia/Tokyo")
        XCTAssertEqual(tokyo, Date(timeIntervalSince1970: 1_788_948_000))
    }

    func testUnknownTimeZoneFallsBackToUTC() {
        let date = MicrosoftGraphDateParser.dateTime("2026-09-09T10:00:00.0000000", timeZoneID: "Not/AZone")
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1_788_948_000))
    }

    func testInvalidDateTimeReturnsNil() {
        XCTAssertNil(MicrosoftGraphDateParser.dateTime("not a date", timeZoneID: "UTC"))
        XCTAssertNil(MicrosoftGraphDateParser.dateTime("2026-09-09", timeZoneID: "UTC"))
        XCTAssertNil(MicrosoftGraphDateParser.dateTime("", timeZoneID: "UTC"))
        XCTAssertNil(MicrosoftGraphDateParser.dateTime("2026-13-01T10:00:00", timeZoneID: "UTC"))
        XCTAssertNil(MicrosoftGraphDateParser.dateTime("2026-02-30T10:00:00", timeZoneID: "UTC"))
        XCTAssertNil(MicrosoftGraphDateParser.dateTime("2026-09-09T24:00:00", timeZoneID: "UTC"))
    }

    func testAllDayDateIsLocalMidnightRegardlessOfTimePart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = MicrosoftGraphDateParser.allDayLocalDate("2026-09-09T00:00:00.0000000", calendar: calendar)
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 9
        XCTAssertEqual(date, calendar.date(from: components))
        XCTAssertNil(MicrosoftGraphDateParser.allDayLocalDate("2026-09", calendar: calendar))
    }

    // MARK: - Field mapping

    func testStatusMapping() {
        XCTAssertEqual(MicrosoftGraphEventMapping.status(isCancelled: true, showAs: "busy"), .canceled)
        XCTAssertEqual(MicrosoftGraphEventMapping.status(isCancelled: true, showAs: "tentative"), .canceled)
        XCTAssertEqual(MicrosoftGraphEventMapping.status(isCancelled: false, showAs: "tentative"), .tentative)
        XCTAssertEqual(MicrosoftGraphEventMapping.status(isCancelled: false, showAs: "busy"), .confirmed)
        XCTAssertEqual(MicrosoftGraphEventMapping.status(isCancelled: false, showAs: "free"), .confirmed)
        XCTAssertEqual(MicrosoftGraphEventMapping.status(isCancelled: false, showAs: nil), .confirmed)
    }

    func testAttendeeResponseMapping() {
        XCTAssertEqual(MicrosoftGraphEventMapping.attendeeStatus(response: "accepted"), .accepted)
        XCTAssertEqual(MicrosoftGraphEventMapping.attendeeStatus(response: "organizer"), .accepted)
        XCTAssertEqual(MicrosoftGraphEventMapping.attendeeStatus(response: "declined"), .declined)
        XCTAssertEqual(MicrosoftGraphEventMapping.attendeeStatus(response: "tentativelyAccepted"), .tentative)
        XCTAssertEqual(MicrosoftGraphEventMapping.attendeeStatus(response: "notResponded"), .pending)
        XCTAssertEqual(MicrosoftGraphEventMapping.attendeeStatus(response: "none"), .pending)
        XCTAssertEqual(MicrosoftGraphEventMapping.attendeeStatus(response: "something-new"), .unknown)
        XCTAssertEqual(MicrosoftGraphEventMapping.attendeeStatus(response: nil), .unknown)
    }

    func testOptionalAttendeeType() {
        XCTAssertTrue(MicrosoftGraphEventMapping.isOptional(attendeeType: "optional"))
        XCTAssertFalse(MicrosoftGraphEventMapping.isOptional(attendeeType: "required"))
        XCTAssertFalse(MicrosoftGraphEventMapping.isOptional(attendeeType: "resource"))
        XCTAssertFalse(MicrosoftGraphEventMapping.isOptional(attendeeType: nil))
    }

    func testConferenceURLPrefersJoinURL() {
        let url = MicrosoftGraphEventMapping.conferenceURL(
            onlineMeetingJoinURL: "https://teams.microsoft.com/l/meetup-join/abc",
            onlineMeetingURL: "https://example.com/other"
        )
        XCTAssertEqual(url?.absoluteString, "https://teams.microsoft.com/l/meetup-join/abc")

        let fallback = MicrosoftGraphEventMapping.conferenceURL(
            onlineMeetingJoinURL: "",
            onlineMeetingURL: "https://example.com/other"
        )
        XCTAssertEqual(fallback?.absoluteString, "https://example.com/other")
        XCTAssertNil(MicrosoftGraphEventMapping.conferenceURL(onlineMeetingJoinURL: nil, onlineMeetingURL: nil))
    }

    func testRecurrenceDetection() {
        XCTAssertTrue(MicrosoftGraphEventMapping.isRecurrent(type: "occurrence", seriesID: nil))
        XCTAssertTrue(MicrosoftGraphEventMapping.isRecurrent(type: "exception", seriesID: nil))
        XCTAssertTrue(MicrosoftGraphEventMapping.isRecurrent(type: "singleInstance", seriesID: "master"))
        XCTAssertFalse(MicrosoftGraphEventMapping.isRecurrent(type: "singleInstance", seriesID: nil))
        XCTAssertFalse(MicrosoftGraphEventMapping.isRecurrent(type: nil, seriesID: ""))
    }

    func testCurrentUserDetectionIsCaseInsensitive() {
        XCTAssertTrue(MicrosoftGraphEventMapping.isCurrentUser(address: "User@Contoso.com", username: "user@contoso.com"))
        XCTAssertFalse(MicrosoftGraphEventMapping.isCurrentUser(address: "other@contoso.com", username: "user@contoso.com"))
        XCTAssertFalse(MicrosoftGraphEventMapping.isCurrentUser(address: nil, username: "user@contoso.com"))
        XCTAssertFalse(MicrosoftGraphEventMapping.isCurrentUser(address: "user@contoso.com", username: nil))
    }

    // MARK: - Configuration

    private let guid = "12345678-90ab-cdef-1234-567890abcdef"

    func testBuildSettingClientIDResolves() throws {
        let config = try MicrosoftGraphConfigurationPolicy.resolve(
            buildClientID: " \(guid) ",
            bundleID: "leits.MeetingBar"
        )
        XCTAssertEqual(config.clientID, guid)
        XCTAssertEqual(config.authorityURL.absoluteString, "https://login.microsoftonline.com/common")
        XCTAssertEqual(config.redirectURI, "msauth.leits.MeetingBar://auth")
        XCTAssertEqual(config.source, .buildSetting)
        XCTAssertTrue(config.isConfigured)
        XCTAssertEqual(config.sourceLabel, "build setting")
    }

    func testPlaceholderOrEmptyBuildSettingIsMissing() throws {
        for value in [nil, "", "   ", "REPLACE_BY_YOUR_MICROSOFT_CLIENT_ID"] {
            let config = try MicrosoftGraphConfigurationPolicy.resolve(
                buildClientID: value,
                bundleID: "leits.MeetingBar"
            )
            XCTAssertEqual(config.source, .missing)
            XCTAssertFalse(config.isConfigured)
            XCTAssertEqual(config.sourceLabel, "missing")
        }
    }

    func testInvalidBuildClientIDThrows() {
        XCTAssertThrowsError(
            try MicrosoftGraphConfigurationPolicy.resolve(
                buildClientID: "not-a-guid",
                bundleID: "leits.MeetingBar"
            )
        ) { error in
            guard case .configurationInvalid? = error as? MicrosoftAuthError else {
                return XCTFail("Expected configurationInvalid, got \(error)")
            }
        }
    }

    // MARK: - URL building

    func testCalendarsURL() throws {
        let url = try MicrosoftGraphURLBuilder.calendarsURL()
        XCTAssertEqual(url.host, "graph.microsoft.com")
        XCTAssertEqual(url.path, "/v1.0/me/calendars")
        XCTAssertTrue(url.query?.contains("$select=id,name,hexColor") ?? false)
        XCTAssertTrue(url.query?.contains("$top=100") ?? false)
    }

    func testCalendarViewURLEscapesCalendarIDOnce() throws {
        let start = Date(timeIntervalSince1970: 1_788_912_000)
        let end = Date(timeIntervalSince1970: 1_788_998_400)
        let url = try MicrosoftGraphURLBuilder.calendarViewURL(
            calendarID: "AAMkAGI2T/G+E=",
            start: start,
            end: end
        )
        XCTAssertEqual(url.path, "/v1.0/me/calendars/AAMkAGI2T/G+E=/calendarView")
        XCTAssertTrue(url.absoluteString.contains("/me/calendars/AAMkAGI2T%2FG%2BE%3D/calendarView"))
        XCTAssertTrue(url.query?.contains("startDateTime=2026-09-09T00:00:00Z") ?? false)
        XCTAssertTrue(url.query?.contains("endDateTime=2026-09-10T00:00:00Z") ?? false)
        XCTAssertTrue(url.query?.contains("$orderby=start/dateTime") ?? false)
        XCTAssertTrue(url.query?.contains("$top=250") ?? false)
        XCTAssertTrue(url.query?.contains("$select=" + MicrosoftGraphURLBuilder.eventSelectFields) ?? false)
    }

    func testNextLinkExtraction() {
        let root: [String: Any] = ["@odata.nextLink": "https://graph.microsoft.com/v1.0/me/calendars?$skip=100"]
        XCTAssertEqual(
            MicrosoftGraphURLBuilder.nextLink(from: root)?.absoluteString,
            "https://graph.microsoft.com/v1.0/me/calendars?$skip=100"
        )
        XCTAssertNil(MicrosoftGraphURLBuilder.nextLink(from: [:]))
    }

    func testNextLinkRejectsForeignOrInsecureHosts() {
        XCTAssertNil(MicrosoftGraphURLBuilder.nextLink(
            from: ["@odata.nextLink": "https://evil.example.com/v1.0/me/calendars?$skip=100"]
        ))
        XCTAssertNil(MicrosoftGraphURLBuilder.nextLink(
            from: ["@odata.nextLink": "http://graph.microsoft.com/v1.0/me/calendars?$skip=100"]
        ))
        XCTAssertEqual(
            MicrosoftGraphURLBuilder.nextLink(
                from: ["@odata.nextLink": "https://graph.microsoft.com/v1.0/me/calendars?$skip=100"]
            )?.absoluteString,
            "https://graph.microsoft.com/v1.0/me/calendars?$skip=100"
        )
    }

    // MARK: - Error descriptions

    func testErrorDescriptionsNameMicrosoft365() {
        XCTAssertEqual(MicrosoftAuthError.notSignedIn.errorDescription, "Microsoft 365 sign-in is required")
        XCTAssertEqual(MicrosoftAuthError.cancelled.errorDescription, "Microsoft 365 sign-in was cancelled")
        XCTAssertTrue(MicrosoftAuthError.configurationMissing.errorDescription?.contains("MICROSOFT_CLIENT_ID") ?? false)
        XCTAssertEqual(
            MicrosoftGraphError.forbiddenCalendar(calendarID: "work", url: calendarViewURL).errorDescription,
            "Microsoft 365 calendar is not accessible: work"
        )
        XCTAssertEqual(
            MicrosoftGraphError.httpStatus(500, code: "X", url: calendarsURL).errorDescription,
            "Microsoft 365 request failed with HTTP 500 (X): \(calendarsURL.absoluteString)"
        )
        XCTAssertTrue(
            MicrosoftGraphError.mailboxNotAvailable(calendarsURL).errorDescription?.contains("mailbox") ?? false
        )
    }
}
