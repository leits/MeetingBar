import XCTest
@testable import MeetingBar

final class ScriptsTests: XCTestCase {
    func testCreateAppleScriptParametersForEvent() {
        // Given: Create a test event with calendar information
        let calendar = MBCalendar(title: "Work Calendar", source: "iCloud")
        let event = MBEvent(
            ID: "test-id",
            title: "Test Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            isAllDay: false,
            attendees: [MBAttendee(name: "Test User", email: "test@example.com")],
            location: "Meeting Room 1",
            notes: "Test Notes",
            recurrent: true,
            meetingLink: MBMeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/123456789")!),
            calendar: calendar
        )

        // When: Create AppleScript parameters
        let parameters = createAppleScriptParametersForEvent(event: event)

        // Then: Verify all parameters are present and in correct order
        XCTAssertEqual(parameters.numberOfItems, 13, "Should have 13 parameters including calendar info")

        // Verify calendar parameters (last two parameters)
        XCTAssertEqual(parameters.atIndex(12)?.stringValue, "iCloud", "Calendar source should be last parameter")
        XCTAssertEqual(parameters.atIndex(11)?.stringValue, "Work Calendar", "Calendar name should be second to last")

        // Verify other parameters maintain their positions
        XCTAssertEqual(parameters.atIndex(10)?.stringValue, "Test Notes", "Notes parameter position")
        XCTAssertEqual(parameters.atIndex(9)?.stringValue, "zoom", "Meeting service parameter position")
        XCTAssertEqual(parameters.atIndex(8)?.stringValue, "https://zoom.us/j/123456789", "Meeting URL parameter position")
        XCTAssertEqual(parameters.atIndex(7)?.int32Value, 1, "Attendee count parameter position")
        XCTAssertTrue(parameters.atIndex(6)?.booleanValue ?? false, "Recurring parameter position")
        XCTAssertEqual(parameters.atIndex(5)?.stringValue, "Meeting Room 1", "Location parameter position")
        XCTAssertNotNil(parameters.atIndex(4)?.dateValue, "End date parameter position")
        XCTAssertNotNil(parameters.atIndex(3)?.dateValue, "Start date parameter position")
        XCTAssertFalse(parameters.atIndex(2)?.booleanValue ?? true, "All-day parameter position")
        XCTAssertEqual(parameters.atIndex(1)?.stringValue, "Test Meeting", "Title parameter position")
        XCTAssertEqual(parameters.atIndex(0)?.stringValue, "test-id", "Event ID parameter position")
    }

    func testCreateAppleScriptParametersWithEmptyCalendarInfo() {
        // Given: Create a test event with minimal calendar information
        let calendar = MBCalendar(title: "", source: "")
        let event = MBEvent(
            ID: "test-id",
            title: "Test Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            isAllDay: false,
            attendees: [],
            location: nil,
            notes: nil,
            recurrent: false,
            meetingLink: nil,
            calendar: calendar
        )

        // When: Create AppleScript parameters
        let parameters = createAppleScriptParametersForEvent(event: event)

        // Then: Verify empty calendar values are handled correctly
        XCTAssertEqual(parameters.atIndex(12)?.stringValue, "", "Empty calendar source should be preserved")
        XCTAssertEqual(parameters.atIndex(11)?.stringValue, "", "Empty calendar name should be preserved")

        // Verify default values for optional parameters
        XCTAssertEqual(parameters.atIndex(10)?.stringValue, "EMPTY", "Empty notes should be 'EMPTY'")
        XCTAssertEqual(parameters.atIndex(9)?.stringValue, "EMPTY", "Empty meeting service should be 'EMPTY'")
        XCTAssertEqual(parameters.atIndex(8)?.stringValue, "EMPTY", "Empty meeting URL should be 'EMPTY'")
        XCTAssertEqual(parameters.atIndex(5)?.stringValue, "EMPTY", "Empty location should be 'EMPTY'")
    }
}
