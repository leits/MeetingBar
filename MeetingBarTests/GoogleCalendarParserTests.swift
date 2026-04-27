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
        XCTAssertEqual(event?.url?.absoluteString, "https://meet.google.com/abc-defg-hij")
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
}
