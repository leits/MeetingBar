//
//  GoogleCalendarParserTests.swift
//  MeetingBarTests
//

import AppAuthCore
import XCTest

@testable import MeetingBar

@MainActor
final class GoogleCalendarParserTests: XCTestCase {
    private let calendar = MBCalendar(
        title: "Calendar",
        id: "calendar-id",
        source: "user@example.com",
        email: "user@example.com",
        color: .black
    )

    func testTimedEventParses() {
        let event = GCEventStore.GCParser.event(
            from: [
                "id": "event-1",
                "updated": "2026-04-24T09:00:00Z",
                "summary": "Standup",
                "status": "confirmed",
                "start": ["dateTime": "2026-04-24T10:00:00Z"],
                "end": ["dateTime": "2026-04-24T10:30:00Z"],
                "organizer": ["email": "organizer@example.com", "name": "Organizer"],
                "attendees": [
                    [
                        "email": "user@example.com",
                        "displayName": "User",
                        "responseStatus": "accepted",
                        "self": true
                    ]
                ],
                "conferenceData": [
                    "entryPoints": [
                        [
                            "entryPointType": "video",
                            "uri": "https://meet.google.com/abc-defg-hij"
                        ]
                    ]
                ]
            ],
            calendar: calendar
        )

        XCTAssertEqual(event?.id, "event-1")
        XCTAssertEqual(event?.title, "Standup")
        XCTAssertEqual(event?.status, .confirmed)
        XCTAssertEqual(event?.organizer?.email, "organizer@example.com")
        XCTAssertEqual(event?.attendees.first?.status, .accepted)
        // Phase 3 PR-B: Google conferenceData URL now flows through the
        // dedicated `conferenceURL` field instead of `url`. The plain
        // `url` field stays nil for Google events because Google Calendar
        // has no per-event "user URL" equivalent of EKEvent.url.
        XCTAssertNil(event?.url)
        XCTAssertEqual(event?.conferenceURL?.absoluteString, "https://meet.google.com/abc-defg-hij")
        // The detector populates meetingLink from conferenceURL via the
        // providerConferenceData source. The Meet URL gets the calendar
        // owner appended as `authuser` so the host's Google identity is
        // used when joining.
        XCTAssertEqual(
            event?.meetingLink?.url.absoluteString,
            "https://meet.google.com/abc-defg-hij?authuser=user@example.com"
        )
        XCTAssertEqual(event?.meetingLink?.service, .meet)
        XCTAssertFalse(event?.isAllDay ?? true)
    }

    func testHtmlLinkBecomesCalendarOpenURL() {
        let event = GCEventStore.GCParser.event(
            from: [
                "id": "event-html",
                "summary": "With web link",
                "status": "confirmed",
                "start": ["dateTime": "2026-04-24T10:00:00Z"],
                "end": ["dateTime": "2026-04-24T10:30:00Z"],
                "htmlLink": "https://www.google.com/calendar/event?eid=abc123"
            ],
            calendar: calendar
        )

        XCTAssertEqual(
            event?.calendarOpenURL?.absoluteString,
            "https://www.google.com/calendar/event?eid=abc123"
        )
    }

    func testMissingHtmlLinkLeavesCalendarOpenURLNil() {
        let event = GCEventStore.GCParser.event(
            from: [
                "id": "event-nolink",
                "summary": "No web link",
                "status": "confirmed",
                "start": ["dateTime": "2026-04-24T10:00:00Z"],
                "end": ["dateTime": "2026-04-24T10:30:00Z"]
            ],
            calendar: calendar
        )

        XCTAssertNil(event?.calendarOpenURL)
    }

    func testAllDayEventParses() {
        let event = GCEventStore.GCParser.event(
            from: [
                "id": "event-2",
                "summary": "OOO",
                "status": "tentative",
                "start": ["date": "2026-04-24"],
                "end": ["date": "2026-04-25"]
            ],
            calendar: calendar
        )

        XCTAssertEqual(event?.id, "event-2")
        XCTAssertEqual(event?.status, .tentative)
        XCTAssertTrue(event?.isAllDay ?? false)
    }

    func testCancelledRecurringEventParsesAttendeeStatuses() {
        let event = GCEventStore.GCParser.event(
            from: [
                "id": "event-3",
                "summary": "Moved meeting",
                "status": "cancelled",
                "recurringEventId": "series-1",
                "start": ["dateTime": "2026-04-24T10:00:00Z"],
                "end": ["dateTime": "2026-04-24T10:30:00Z"],
                "attendees": [
                    ["email": "pending@example.com", "responseStatus": "needsAction", "optional": true],
                    ["email": "tentative@example.com", "responseStatus": "tentative"],
                    ["email": "declined@example.com", "responseStatus": "declined"],
                    ["email": "unknown@example.com", "responseStatus": "unexpected"]
                ]
            ],
            calendar: calendar
        )

        XCTAssertEqual(event?.status, .canceled)
        XCTAssertTrue(event?.recurrent ?? false)
        XCTAssertEqual(event?.attendees.map(\.status) ?? [], [.pending, .tentative, .declined, .unknown])
        XCTAssertEqual(event?.attendees.first?.optional, true)
    }

    func testConferenceDataWithoutUsableVideoURLFallsBackToNotesLink() {
        let event = GCEventStore.GCParser.event(
            from: [
                "id": "event-4",
                "summary": "Fallback link",
                "start": ["dateTime": "2026-04-24T10:00:00Z"],
                "end": ["dateTime": "2026-04-24T10:30:00Z"],
                "description": "Join backup: https://us02web.zoom.us/j/12345",
                "conferenceData": [
                    "entryPoints": [
                        [
                            "entryPointType": "video"
                        ]
                    ]
                ]
            ],
            calendar: calendar
        )

        XCTAssertNil(event?.conferenceURL)
        XCTAssertEqual(event?.meetingLink?.service, .zoom)
        XCTAssertEqual(event?.meetingLink?.url.absoluteString, "https://us02web.zoom.us/j/12345")
    }

    func testMalformedEventReturnsNil() {
        XCTAssertNil(GCEventStore.GCParser.event(from: ["summary": "Missing id"], calendar: calendar))
        XCTAssertNil(GCEventStore.GCParser.event(from: ["id": "missing-dates"], calendar: calendar))
        XCTAssertNil(
            GCEventStore.GCParser.event(
                from: [
                    "id": "bad-date",
                    "start": ["dateTime": "not-a-date"],
                    "end": ["dateTime": "2026-04-24T10:30:00Z"]
                ],
                calendar: calendar
            )
        )
        XCTAssertNil(
            GCEventStore.GCParser.event(
                from: [
                    "id": "bad-all-day-date",
                    "start": ["date": "not-a-date"],
                    "end": ["date": "2026-04-25"]
                ],
                calendar: calendar
            )
        )
    }

    func testHTTP401AfterRetryRequiresAuthClear() {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!

        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 401,
            url: url,
            calendarID: nil,
            retrying: true
        )

        XCTAssertEqual(decision, .clearAuthAndThrowAuthRequired)
    }

    func testHTTP403AfterRetryIsForbiddenCalendarWithoutAuthClear() {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/holiday/events")!

        let decision = GoogleHTTPStatusPolicy.classify(
            statusCode: 403,
            url: url,
            calendarID: "holiday",
            retrying: true
        )

        XCTAssertEqual(
            decision,
            .throwError(.forbiddenCalendar(calendarID: "holiday", url: url))
        )
    }

    func testOneForbiddenCalendarStillReturnsSuccessfulEvents() throws {
        let event = makeFakeEvent(
            id: "ok",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(120)
        )
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/bad/events")!

        let events = try GoogleCalendarBatchPolicy.finish(
            events: [event],
            successfulCalendars: 1,
            forbiddenErrors: [GoogleCalendarError.forbiddenCalendar(calendarID: "bad", url: url)]
        )

        XCTAssertEqual(events, [event])
    }

    func testAllForbiddenCalendarsThrowsRepresentativeError() {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/bad/events")!
        let error = GoogleCalendarError.forbiddenCalendar(calendarID: "bad", url: url)

        XCTAssertThrowsError(
            try GoogleCalendarBatchPolicy.finish(
                events: [],
                successfulCalendars: 0,
                forbiddenErrors: [error]
            )
        ) { thrown in
            XCTAssertEqual(thrown as? GoogleCalendarError, error)
        }
    }

    func testMissingItemsErrorStillDescribesMalformedResponse() {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!

        XCTAssertEqual(
            GoogleCalendarError.missingItems(url).errorDescription,
            "Google Calendar response did not contain an items array: \(url.absoluteString)"
        )
    }

    func testEventsURLPercentEncodesSpecialCalendarIDCharacters() throws {
        let url = try GCEventStore.eventsURL(
            calendarID: "group.v.calendar.google.com#contacts+team@example.com",
            timeMin: "2026-01-01T00:00:00Z",
            timeMax: "2026-01-02T00:00:00Z"
        )

        XCTAssertNil(url.fragment)
        XCTAssertTrue(
            url.absoluteString.contains(
                "/calendar/v3/calendars/group.v.calendar.google.com%23contacts+team@example.com/events"
            )
        )

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(queryItems?.first { $0.name == "singleEvents" }?.value, "true")
        XCTAssertEqual(queryItems?.first { $0.name == "orderBy" }?.value, "startTime")
        XCTAssertEqual(queryItems?.first { $0.name == "eventTypes" }?.value, "default")
        XCTAssertEqual(queryItems?.first { $0.name == "timeMin" }?.value, "2026-01-01T00:00:00Z")
        XCTAssertEqual(queryItems?.first { $0.name == "timeMax" }?.value, "2026-01-02T00:00:00Z")
    }
}

@MainActor
final class GoogleAuthStateTests: XCTestCase {
    func testLatestTokenResponseWithoutRefreshTokenKeepsReusableSession() throws {
        let authorizationResponse = OIDAuthorizationResponse(
            request: authorizationRequest(),
            parameters: ["code": "authorization-code" as NSString]
        )
        let tokenRequest = try XCTUnwrap(authorizationResponse.tokenExchangeRequest())
        let initialTokenResponse = tokenResponse(
            request: tokenRequest,
            accessToken: "access-token-1",
            refreshToken: "refresh-token-1"
        )
        let state = OIDAuthState(
            authorizationResponse: authorizationResponse,
            tokenResponse: initialTokenResponse
        )

        state.update(
            with: tokenResponse(
                request: tokenRequest,
                accessToken: "access-token-2",
                refreshToken: nil
            ),
            error: nil
        )

        XCTAssertNil(state.lastTokenResponse?.refreshToken)
        XCTAssertEqual(state.refreshToken, "refresh-token-1")
        XCTAssertTrue(GCEventStore.hasReusableSession(state))
        XCTAssertTrue(GCEventStore.shouldSkipSignIn(forcePrompt: false, state: state))
        XCTAssertFalse(GCEventStore.shouldSkipSignIn(forcePrompt: true, state: state))
    }

    func testSessionWithoutPersistedRefreshTokenRequiresAuthorization() throws {
        let authorizationResponse = OIDAuthorizationResponse(
            request: authorizationRequest(),
            parameters: ["code": "authorization-code" as NSString]
        )
        let tokenRequest = try XCTUnwrap(authorizationResponse.tokenExchangeRequest())
        let state = OIDAuthState(
            authorizationResponse: authorizationResponse,
            tokenResponse: tokenResponse(
                request: tokenRequest,
                accessToken: "access-token",
                refreshToken: nil
            )
        )

        XCTAssertNil(state.refreshToken)
        XCTAssertFalse(GCEventStore.hasReusableSession(state))
        XCTAssertFalse(GCEventStore.shouldSkipSignIn(forcePrompt: false, state: state))
    }

    private func authorizationRequest() -> OIDAuthorizationRequest {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
        return OIDAuthorizationRequest(
            configuration: configuration,
            clientId: "client-id",
            clientSecret: nil,
            scopes: ["email"],
            redirectURL: URL(string: "com.test.app:/oauthredirect")!,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
    }

    private func tokenResponse(
        request: OIDTokenRequest,
        accessToken: String,
        refreshToken: String?
    ) -> OIDTokenResponse {
        var parameters: [String: NSObject & NSCopying] = [
            "access_token": accessToken as NSString,
            "token_type": "Bearer" as NSString,
            "expires_in": 3600 as NSNumber
        ]
        if let refreshToken {
            parameters["refresh_token"] = refreshToken as NSString
        }
        return OIDTokenResponse(request: request, parameters: parameters)
    }
}
