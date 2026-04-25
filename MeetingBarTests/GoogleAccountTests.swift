//
//  GoogleAccountTests.swift
//  MeetingBar
//
//  Created for multi-account Google Calendar support.
//  Copyright © 2026 Andrii Leitsius. All rights reserved.
//

@testable import MeetingBar
import Defaults
import XCTest

@MainActor
final class GoogleAccountTests: BaseTestCase {

    func test_googleAccountCreation() {
        let account = GoogleAccount(id: "test-id", email: "test@example.com")

        XCTAssertEqual(account.id, "test-id")
        XCTAssertEqual(account.email, "test@example.com")
    }

    func test_googleAccountHashable() {
        let account1 = GoogleAccount(id: "id-1", email: "a@example.com")
        let account2 = GoogleAccount(id: "id-1", email: "a@example.com")
        let account3 = GoogleAccount(id: "id-2", email: "b@example.com")

        XCTAssertEqual(account1, account2)
        XCTAssertEqual(account1.hashValue, account2.hashValue)
        XCTAssertNotEqual(account1, account3)
    }

    func test_googleAccountCodable() throws {
        let account = GoogleAccount(id: "enc-id", email: "encoded@example.com")
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(GoogleAccount.self, from: data)

        XCTAssertEqual(decoded.id, "enc-id")
        XCTAssertEqual(decoded.email, "encoded@example.com")
    }

    func test_googleAccountPersistedInDefaults() {
        let accounts = [
            GoogleAccount(id: "personal", email: "personal@example.com"),
            GoogleAccount(id: "work", email: "work@example.com")
        ]

        Defaults[.googleAccounts] = accounts

        let loaded = Defaults[.googleAccounts]
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].email, "personal@example.com")
        XCTAssertEqual(loaded[1].email, "work@example.com")
    }

    func test_googleAccountDefaultsEmptyByDefault() {
        XCTAssertTrue(Defaults[.googleAccounts].isEmpty)
    }
}

@MainActor
final class MultiAccountCalendarTests: BaseTestCase {

    func test_calendarIdPrefixing() {
        let accountId = "acc-123"
        let originalCalendarId = "primary"
        let prefixedId = "\(accountId):\(originalCalendarId)"

        XCTAssertEqual(prefixedId, "acc-123:primary")

        let extractedPrefix = prefixedId.components(separatedBy: ":").first ?? ""
        XCTAssertEqual(extractedPrefix, accountId)

        let extractedOriginal = String(prefixedId.dropFirst("\(accountId):".count))
        XCTAssertEqual(extractedOriginal, originalCalendarId)
    }

    func test_multiAccountCalendarGrouping() {
        let cal1 = MBCalendar(title: "Personal", id: "acc1:primary", source: "personal@example.com", email: "personal@example.com", color: .blue)
        let cal2 = MBCalendar(title: "Work", id: "acc2:primary", source: "work@example.com", email: "work@example.com", color: .red)
        let cal3 = MBCalendar(title: "Birthdays", id: "acc1:birthday", source: "personal@example.com", email: "personal@example.com", color: .green)

        let calendars = [cal1, cal2, cal3]
        let grouped = Dictionary(grouping: calendars, by: \.source)

        XCTAssertEqual(grouped["personal@example.com"]?.count, 2)
        XCTAssertEqual(grouped["work@example.com"]?.count, 1)
    }

    func test_calendarIdsAreUniqueAcrossAccounts() {
        let personalCalId = "acc1:primary"
        let workCalId = "acc2:primary"

        XCTAssertNotEqual(personalCalId, workCalId)

        let allIds = [personalCalId, workCalId]
        XCTAssertEqual(allIds.count, Set(allIds).count)
    }

    func test_selectedCalendarIDsCleanedOnAccountRemoval() async {
        let accountId = "acc-to-remove"
        let keptAccountId = "acc-kept"

        Defaults[.selectedCalendarIDs] = [
            "\(accountId):primary",
            "\(accountId):meetings",
            "\(keptAccountId):primary",
            "unprefixed-calendar"
        ]

        let account = GoogleAccount(id: accountId, email: "remove@example.com")
        Defaults[.googleAccounts] = [account]

        await GCEventStore.shared.removeAccount(account)

        XCTAssertEqual(Defaults[.selectedCalendarIDs].count, 2)
        XCTAssertTrue(Defaults[.selectedCalendarIDs].contains("\(keptAccountId):primary"))
        XCTAssertTrue(Defaults[.selectedCalendarIDs].contains("unprefixed-calendar"))
        XCTAssertFalse(Defaults[.selectedCalendarIDs].contains("\(accountId):primary"))
        XCTAssertFalse(Defaults[.selectedCalendarIDs].contains("\(accountId):meetings"))
        XCTAssertTrue(Defaults[.googleAccounts].isEmpty)
    }

    func test_calendarIdExtractionWithFirstColon() {
        let id1 = "acc1:primary"
        let id2 = "acc2:calendar:with:colons"
        let id3 = "no-colon"

        if let idx = id1.firstIndex(of: ":") {
            XCTAssertEqual(String(id1[..<idx]), "acc1")
            XCTAssertEqual(String(id1[id1.index(after: idx)...]), "primary")
        }

        if let idx = id2.firstIndex(of: ":") {
            XCTAssertEqual(String(id2[..<idx]), "acc2")
            XCTAssertEqual(String(id2[id2.index(after: idx)...]), "calendar:with:colons")
        }

        XCTAssertNil(id3.firstIndex(of: ":"))
    }

    func test_calendarIdPrefixCheck() {
        let accountId = "test-acc"
        let prefix = "\(accountId):"

        XCTAssertTrue("\(accountId):primary".hasPrefix(prefix))
        XCTAssertTrue("\(accountId):nested:cal".hasPrefix(prefix))
        XCTAssertFalse("other-acc:primary".hasPrefix(prefix))
        XCTAssertFalse("primary".hasPrefix(prefix))
        XCTAssertFalse("test-acc".hasPrefix(prefix))
    }
}

@MainActor
final class GCParserTests: BaseTestCase {

    private var calendar: MBCalendar {
        MBCalendar(title: "Test", id: "acc:cal", source: "test@example.com", email: "test@example.com", color: .blue)
    }

    func test_parseMinimalEvent() {
        let item: [String: Any] = [
            "id": "evt-1",
            "status": "confirmed",
            "updated": "2024-01-15T10:00:00Z",
            "start": ["dateTime": "2024-01-15T10:00:00Z"],
            "end": ["dateTime": "2024-01-15T11:00:00Z"]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.id, "evt-1")
        XCTAssertEqual(event?.status, .confirmed)
        XCTAssertFalse(event?.isAllDay ?? true)
        XCTAssertEqual(event?.title, "No title")
        XCTAssertNil(event?.url)
        XCTAssertNil(event?.location)
        XCTAssertNil(event?.notes)
        XCTAssertTrue(event?.attendees.isEmpty ?? true)
    }

    func test_parseEventWithAllFields() {
        let item: [String: Any] = [
            "id": "evt-full",
            "status": "tentative",
            "updated": "2024-06-01T08:00:00Z",
            "summary": "Team Standup",
            "description": "Daily sync",
            "location": "Room 42",
            "start": ["dateTime": "2024-06-01T09:00:00Z"],
            "end": ["dateTime": "2024-06-01T09:30:00Z"],
            "recurringEventId": "rec-123",
            "organizer": ["email": "boss@example.com", "name": "Boss"],
            "conferenceData": [
                "entryPoints": [
                    ["entryPointType": "video", "uri": "https://meet.google.com/abc-def"]
                ]
            ],
            "attendees": [
                ["email": "a@example.com", "displayName": "Alice", "responseStatus": "accepted", "optional": false, "self": true],
                ["email": "b@example.com", "displayName": "Bob", "responseStatus": "needsAction", "optional": true, "self": false]
            ]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.id, "evt-full")
        XCTAssertEqual(event?.title, "Team Standup")
        XCTAssertEqual(event?.status, .tentative)
        XCTAssertEqual(event?.notes, "Daily sync")
        XCTAssertEqual(event?.location, "Room 42")
        XCTAssertEqual(event?.url, URL(string: "https://meet.google.com/abc-def"))
        XCTAssertEqual(event?.organizer?.email, "boss@example.com")
        XCTAssertEqual(event?.organizer?.name, "Boss")
        XCTAssertTrue(event?.recurrent ?? false)

        let attendees = event?.attendees ?? []
        XCTAssertEqual(attendees.count, 2)

        let alice = attendees[0]
        XCTAssertEqual(alice.email, "a@example.com")
        XCTAssertEqual(alice.name, "Alice")
        XCTAssertEqual(alice.status, .accepted)
        XCTAssertFalse(alice.optional)
        XCTAssertTrue(alice.isCurrentUser)

        let bob = attendees[1]
        XCTAssertEqual(bob.email, "b@example.com")
        XCTAssertEqual(bob.name, "Bob")
        XCTAssertEqual(bob.status, .pending)
        XCTAssertTrue(bob.optional)
        XCTAssertFalse(bob.isCurrentUser)
    }

    func test_parseAllDayEvent() {
        let item: [String: Any] = [
            "id": "evt-allday",
            "status": "confirmed",
            "updated": "2024-12-25T00:00:00Z",
            "summary": "Christmas",
            "start": ["date": "2024-12-25"],
            "end": ["date": "2024-12-26"]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertNotNil(event)
        XCTAssertTrue(event?.isAllDay ?? false)
        XCTAssertEqual(event?.title, "Christmas")
    }

    func test_parseCancelledEvent() {
        let item: [String: Any] = [
            "id": "evt-cancelled",
            "status": "cancelled",
            "updated": "2024-03-01T12:00:00Z",
            "start": ["dateTime": "2024-03-01T14:00:00Z"],
            "end": ["dateTime": "2024-03-01T15:00:00Z"]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertEqual(event?.status, .canceled)
    }

    func test_parseEventWithUnknownStatus() {
        let item: [String: Any] = [
            "id": "evt-unknown",
            "status": "some_weird_status",
            "updated": "2024-01-01T00:00:00Z",
            "start": ["dateTime": "2024-01-01T10:00:00Z"],
            "end": ["dateTime": "2024-01-01T11:00:00Z"]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertEqual(event?.status, MBEventStatus.none)
    }

    func test_parseEventWithoutAttendees() {
        let item: [String: Any] = [
            "id": "evt-solo",
            "status": "confirmed",
            "updated": "2024-01-01T00:00:00Z",
            "start": ["dateTime": "2024-01-01T10:00:00Z"],
            "end": ["dateTime": "2024-01-01T11:00:00Z"]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertTrue(event?.attendees.isEmpty ?? true)
    }

    func test_parseEventWithoutConferenceData() {
        let item: [String: Any] = [
            "id": "evt-no-video",
            "status": "confirmed",
            "updated": "2024-01-01T00:00:00Z",
            "start": ["dateTime": "2024-01-01T10:00:00Z"],
            "end": ["dateTime": "2024-01-01T11:00:00Z"]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertNil(event?.url)
    }

    func test_parseEventWithMultipleEntryPoints() {
        let item: [String: Any] = [
            "id": "evt-multi-entry",
            "status": "confirmed",
            "updated": "2024-01-01T00:00:00Z",
            "start": ["dateTime": "2024-01-01T10:00:00Z"],
            "end": ["dateTime": "2024-01-01T11:00:00Z"],
            "conferenceData": [
                "entryPoints": [
                    ["entryPointType": "phone", "uri": "tel:+1234567890"],
                    ["entryPointType": "video", "uri": "https://zoom.us/j/123"],
                    ["entryPointType": "more", "uri": "https://example.com"]
                ]
            ]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertEqual(event?.url, URL(string: "https://zoom.us/j/123"))
    }

    func test_parseEventAttendeeStatuses() {
        let statuses = ["accepted", "declined", "tentative", "needsAction", "unknown_status"]
        let expectedStatuses: [MBEventAttendeeStatus] = [.accepted, .declined, .tentative, .pending, .unknown]

        for (index, status) in statuses.enumerated() {
            let item: [String: Any] = [
                "id": "evt-\(index)",
                "status": "confirmed",
                "updated": "2024-01-01T00:00:00Z",
                "start": ["dateTime": "2024-01-01T10:00:00Z"],
                "end": ["dateTime": "2024-01-01T11:00:00Z"],
                "attendees": [
                    ["email": "user\(index)@example.com", "responseStatus": status, "optional": false, "self": false]
                ]
            ]

            let event = GCEventStore.GCParser.event(from: item, calendar: calendar)
            XCTAssertEqual(event?.attendees.first?.status, expectedStatuses[index], "Failed for status: \(status)")
        }
    }
}
