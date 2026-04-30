//
//  GoogleCalendarParserTests.swift
//  MeetingBarTests
//

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
}
