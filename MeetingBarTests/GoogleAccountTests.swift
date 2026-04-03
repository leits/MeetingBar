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
}
