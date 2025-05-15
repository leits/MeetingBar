@testable import MeetingBar
import XCTest

final class ScriptsTests: XCTestCase {
    func testCreateAppleScriptParametersForEvent() {
        // Given: Create a test event with calendar information
        let calendar = MBCalendar(title: "Work Calendar", id: "x", source: "iCloud", email: nil, color: .black)
        let event = MBEvent(
            id: "test-id",
            lastModifiedDate: nil,
            title: "Test Meeting",
            status: .confirmed,
            notes: "Test Notes",
            location: "Meeting Room 1",
            url: URL(string: "https://zoom.us/j/5551112222")!,
            organizer: nil,
            attendees: [MBEventAttendee(email: nil, status: .accepted)], startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            isAllDay: false,
            recurrent: true,
            calendar: calendar
        )

        // When: Create AppleScript parameters
        let parameters = createAppleScriptParametersForEvent(event: event)
        print(parameters)

        // Then: Verify all parameters are present and in correct order
        XCTAssertEqual(parameters.numberOfItems, 13, "Should have 13 parameters including calendar info")

        // Verify calendar parameters (last two parameters)
        XCTAssertEqual(parameters.atIndex(13)?.stringValue, "iCloud", "Calendar source should be last parameter")
        XCTAssertEqual(parameters.atIndex(12)?.stringValue, "Work Calendar", "Calendar name should be second to last")

        // Verify other parameters maintain their positions
        XCTAssertEqual(parameters.atIndex(11)?.stringValue, "Test Notes", "Notes parameter position")
        XCTAssertEqual(parameters.atIndex(10)?.stringValue, "Zoom", "Meeting service parameter position")
        XCTAssertEqual(parameters.atIndex(9)?.stringValue, "https://zoom.us/j/5551112222", "Meeting URL parameter position")
        XCTAssertEqual(parameters.atIndex(8)?.int32Value, 1, "Attendee count parameter position")
        XCTAssertTrue(parameters.atIndex(7)?.booleanValue ?? false, "Recurring parameter position")
        XCTAssertEqual(parameters.atIndex(6)?.stringValue, "Meeting Room 1", "Location parameter position")
        XCTAssertNotNil(parameters.atIndex(5)?.dateValue, "End date parameter position")
        XCTAssertNotNil(parameters.atIndex(4)?.dateValue, "Start date parameter position")
        XCTAssertFalse(parameters.atIndex(3)?.booleanValue ?? true, "All-day parameter position")
        XCTAssertEqual(parameters.atIndex(2)?.stringValue, "Test Meeting", "Title parameter position")
        XCTAssertEqual(parameters.atIndex(1)?.stringValue, "test-id", "Event ID parameter position")
    }

    func testCreateAppleScriptParametersWithEmptyCalendarInfo() {
        // Given: Create a test event with minimal calendar information
        let calendar = MBCalendar(title: "", id: "", source: "", email: nil, color: .black)

        let event = MBEvent(
            id: "test_event",
            lastModifiedDate: nil,
            title: "Test event",
            status: .confirmed,
            notes: nil,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: Calendar.current.date(byAdding: .minute, value: 3, to: Date())!,
            endDate: Calendar.current.date(byAdding: .minute, value: 33, to: Date())!,
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )

        // When: Create AppleScript parameters
        let parameters = createAppleScriptParametersForEvent(event: event)

        // Then: Verify empty calendar values are handled correctly
        XCTAssertEqual(parameters.atIndex(13)?.stringValue, "", "Empty calendar source should be preserved")
        XCTAssertEqual(parameters.atIndex(12)?.stringValue, "", "Empty calendar name should be preserved")

        // Verify default values for optional parameters
        XCTAssertEqual(parameters.atIndex(11)?.stringValue, "EMPTY", "Empty notes should be 'EMPTY'")
        XCTAssertEqual(parameters.atIndex(10)?.stringValue, "EMPTY", "Empty meeting service should be 'EMPTY'")
        XCTAssertEqual(parameters.atIndex(9)?.stringValue, "EMPTY", "Empty meeting URL should be 'EMPTY'")
        XCTAssertEqual(parameters.atIndex(6)?.stringValue, "EMPTY", "Empty location should be 'EMPTY'")
    }
}
