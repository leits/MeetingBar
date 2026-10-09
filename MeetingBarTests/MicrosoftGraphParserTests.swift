//
//  MicrosoftGraphParserTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class MicrosoftGraphParserTests: XCTestCase {
    private let calendar = MBCalendar(
        title: "Calendar",
        id: "calendar-id",
        source: "user@contoso.com",
        email: "user@contoso.com",
        color: .black
    )

    private func event(from item: [String: Any]) -> MBEvent? {
        MicrosoftGraphEventStore.MSGraphParser.event(
            from: item,
            calendar: calendar,
            username: "user@contoso.com"
        )
    }

    func testTimedEventParses() {
        let parsed = event(from: [
            "id": "event-1",
            "subject": "Standup",
            "showAs": "busy",
            "isCancelled": false,
            "lastModifiedDateTime": "2026-09-09T08:00:00.0000000",
            "start": ["dateTime": "2026-09-09T10:00:00.0000000", "timeZone": "UTC"],
            "end": ["dateTime": "2026-09-09T10:30:00.0000000", "timeZone": "UTC"],
            "organizer": ["emailAddress": ["address": "boss@contoso.com", "name": "Boss"]],
            "attendees": [
                [
                    "emailAddress": ["address": "user@contoso.com", "name": "User"],
                    "type": "required",
                    "status": ["response": "accepted"]
                ]
            ],
            "onlineMeeting": ["joinUrl": "https://teams.microsoft.com/l/meetup-join/abc"],
            "webLink": "https://outlook.office365.com/owa/?itemid=abc"
        ])

        XCTAssertEqual(parsed?.id, "event-1")
        XCTAssertEqual(parsed?.title, "Standup")
        XCTAssertEqual(parsed?.status, .confirmed)
        XCTAssertEqual(parsed?.organizer?.email, "boss@contoso.com")
        XCTAssertEqual(parsed?.startDate, Date(timeIntervalSince1970: 1_788_948_000))
        XCTAssertFalse(parsed?.isAllDay ?? true)
        XCTAssertNil(parsed?.url)
        XCTAssertEqual(
            parsed?.conferenceURL?.absoluteString,
            "https://teams.microsoft.com/l/meetup-join/abc"
        )
        XCTAssertEqual(parsed?.meetingLink?.service, .teams)
        XCTAssertEqual(
            parsed?.calendarOpenURL?.absoluteString,
            "https://outlook.office365.com/owa/?itemid=abc"
        )
        XCTAssertEqual(parsed?.attendees.first?.status, .accepted)
    }

    func testAllDayEventUsesLocalMidnight() {
        let parsed = event(from: [
            "id": "event-all-day",
            "subject": "Company holiday",
            "isAllDay": true,
            "start": ["dateTime": "2026-09-09T00:00:00.0000000", "timeZone": "UTC"],
            "end": ["dateTime": "2026-09-10T00:00:00.0000000", "timeZone": "UTC"]
        ])

        XCTAssertTrue(parsed?.isAllDay ?? false)
        XCTAssertEqual(parsed?.startDate, Calendar.current.startOfDay(for: parsed!.startDate))
    }

    func testSelfAttendeeSynthesizedFromResponseStatus() {
        let parsed = event(from: [
            "id": "event-declined",
            "subject": "Optional sync",
            "start": ["dateTime": "2026-09-09T10:00:00.0000000", "timeZone": "UTC"],
            "end": ["dateTime": "2026-09-09T10:30:00.0000000", "timeZone": "UTC"],
            "organizer": ["emailAddress": ["address": "boss@contoso.com", "name": "Boss"]],
            "attendees": [
                ["emailAddress": ["address": "other@contoso.com"], "status": ["response": "accepted"]]
            ],
            "responseStatus": ["response": "declined"]
        ])

        let currentUser = parsed?.attendees.first { $0.isCurrentUser }
        XCTAssertNotNil(currentUser)
        XCTAssertEqual(currentUser?.status, .declined)
        XCTAssertEqual(parsed?.participationStatus, .declined)
    }

    func testCancelledEventMapsToCanceled() {
        let parsed = event(from: [
            "id": "event-cancelled",
            "subject": "Cancelled",
            "isCancelled": true,
            "showAs": "free",
            "start": ["dateTime": "2026-09-09T10:00:00.0000000", "timeZone": "UTC"],
            "end": ["dateTime": "2026-09-09T10:30:00.0000000", "timeZone": "UTC"]
        ])

        XCTAssertEqual(parsed?.status, .canceled)
    }

    func testTentativeShowAsMapsToTentative() {
        let parsed = event(from: [
            "id": "event-tentative",
            "subject": "Maybe",
            "showAs": "tentative",
            "start": ["dateTime": "2026-09-09T10:00:00.0000000", "timeZone": "UTC"],
            "end": ["dateTime": "2026-09-09T10:30:00.0000000", "timeZone": "UTC"]
        ])

        XCTAssertEqual(parsed?.status, .tentative)
    }

    func testRecurringOccurrenceMarksRecurrent() {
        let parsed = event(from: [
            "id": "event-occurrence",
            "subject": "Weekly",
            "type": "occurrence",
            "seriesMasterId": "series-1",
            "start": ["dateTime": "2026-09-09T10:00:00.0000000", "timeZone": "UTC"],
            "end": ["dateTime": "2026-09-09T10:30:00.0000000", "timeZone": "UTC"]
        ])

        XCTAssertTrue(parsed?.recurrent ?? false)
    }

    func testOnlineMeetingUrlFallback() {
        let parsed = event(from: [
            "id": "event-fallback",
            "subject": "Legacy Teams",
            "onlineMeetingUrl": "https://teams.microsoft.com/l/meetup-join/legacy",
            "start": ["dateTime": "2026-09-09T10:00:00.0000000", "timeZone": "UTC"],
            "end": ["dateTime": "2026-09-09T10:30:00.0000000", "timeZone": "UTC"]
        ])

        XCTAssertEqual(
            parsed?.conferenceURL?.absoluteString,
            "https://teams.microsoft.com/l/meetup-join/legacy"
        )
    }

    func testMalformedEventsReturnNil() {
        XCTAssertNil(event(from: ["subject": "No id"]))
        XCTAssertNil(event(from: ["id": "no-dates", "subject": "No dates"]))
        XCTAssertNil(event(from: [
            "id": "bad-dates",
            "start": ["dateTime": "not a date", "timeZone": "UTC"],
            "end": ["dateTime": "also bad", "timeZone": "UTC"]
        ]))
    }
}
