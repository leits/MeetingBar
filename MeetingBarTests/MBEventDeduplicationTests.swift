//
//  MBEventDeduplicationTests.swift
//  MeetingBar
//

import XCTest

@testable import MeetingBar

final class MBEventDeduplicationTests: BaseTestCase {
    func testPrefersCopyWithResolvedCurrentUserAttendee() {
        let start = Date()
        let end = start.addingTimeInterval(1800)

        // Same event ("Jordan / Dalila Recurring") fetched twice because it's
        // visible through two selected calendars. Only the copy fetched via
        // the calendar the user was actually invited on resolves their own
        // attendee record.
        let unresolvedCopy = makeFakeEvent(
            id: "dalila-recurring-0917",
            start: start,
            end: end,
            attendees: [
                MBEventAttendee(email: "dalila@example.com", status: .accepted)
            ]
        )
        let resolvedCopy = makeFakeEvent(
            id: "dalila-recurring-0917",
            start: start,
            end: end,
            attendees: [
                MBEventAttendee(email: "dalila@example.com", status: .accepted),
                MBEventAttendee(email: "jordan@example.com", status: .accepted, isCurrentUser: true)
            ]
        )

        let result = [unresolvedCopy, resolvedCopy].deduplicatedPreferringResolvedAttendee()
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].attendees.contains { $0.isCurrentUser })

        // Order shouldn't matter.
        let reversedResult = [resolvedCopy, unresolvedCopy].deduplicatedPreferringResolvedAttendee()
        XCTAssertEqual(reversedResult.count, 1)
        XCTAssertTrue(reversedResult[0].attendees.contains { $0.isCurrentUser })
    }
}
