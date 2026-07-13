import Carbon
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
            attendees: [
                MBEventAttendee(email: "j@s.com", name: "John Smith", status: .accepted),
                MBEventAttendee(email: "p@s.com", name: "Olivia Smith", status: .accepted)
            ],
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            isAllDay: false,
            recurrent: true,
            calendar: calendar
        )

        // When: Create AppleScript parameters
        let parameters = createAppleScriptParametersForEvent(event: event)

        // Then: Verify all parameters are present and in correct order
        XCTAssertEqual(parameters.numberOfItems, 14, "Should have 14 parameters")

        // Verify calendar parameters (last two parameters)
        XCTAssertEqual(parameters.atIndex(14)?.stringValue, "John Smith <j@s.com>, Olivia Smith <p@s.com>", "Calendar source should be last parameter")
        XCTAssertEqual(parameters.atIndex(13)?.stringValue, "iCloud", "Calendar source should be last parameter")
        XCTAssertEqual(parameters.atIndex(12)?.stringValue, "Work Calendar", "Calendar name should be second to last")

        // Verify other parameters maintain their positions
        XCTAssertEqual(parameters.atIndex(11)?.stringValue, "Test Notes", "Notes parameter position")
        XCTAssertEqual(parameters.atIndex(10)?.stringValue, "Zoom", "Meeting service parameter position")
        XCTAssertEqual(parameters.atIndex(9)?.stringValue, "https://zoom.us/j/5551112222", "Meeting URL parameter position")
        XCTAssertEqual(parameters.atIndex(8)?.int32Value, 2, "Attendee count parameter position")
        XCTAssertTrue(parameters.atIndex(7)?.booleanValue ?? false, "Recurring parameter position")
        XCTAssertEqual(parameters.atIndex(6)?.stringValue, "Meeting Room 1", "Location parameter position")
        XCTAssertNotNil(parameters.atIndex(5)?.dateValue, "End date parameter position")
        XCTAssertNotNil(parameters.atIndex(4)?.dateValue, "Start date parameter position")
        XCTAssertFalse(parameters.atIndex(3)?.booleanValue ?? true, "All-day parameter position")
        XCTAssertEqual(parameters.atIndex(2)?.stringValue, "Test Meeting", "Title parameter position")
        XCTAssertEqual(parameters.atIndex(1)?.stringValue, "test-id", "Event ID parameter position")
    }

    func testEventIdParameterUsesScriptIdentifierNotInternalId() {
        // scriptIdentifier diverges from id for EventKit occurrences: id carries
        // a per-occurrence suffix for dedup, but meetingStart scripts must still
        // receive the raw identifier they were written against.
        let calendar = MBCalendar(title: "Work Calendar", id: "x", source: "iCloud", email: nil, color: .black)
        let event = MBEvent(
            id: "raw-id:1751610600",
            scriptIdentifier: "raw-id",
            lastModifiedDate: nil,
            title: "Standup",
            status: .confirmed,
            notes: nil,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            isAllDay: false,
            recurrent: true,
            calendar: calendar
        )

        let parameters = createAppleScriptParametersForEvent(event: event)

        XCTAssertEqual(
            parameters.atIndex(1)?.stringValue,
            "raw-id",
            "meetingStart eventId must be scriptIdentifier (raw), not the occurrence-composed id"
        )
        XCTAssertNotEqual(parameters.atIndex(1)?.stringValue, event.id)
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

    func testCreateAppleScriptEventCarriesDocumentedJoinPayload() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let attendees = [
            MBEventAttendee(email: "one@example.com", name: "One", status: .accepted),
            MBEventAttendee(email: "two@example.com", name: "Two", status: .accepted)
        ]
        let event = MBEvent(
            id: "join-event",
            lastModifiedDate: start,
            title: "Join payload",
            status: .confirmed,
            notes: "Agenda",
            location: "Room 42",
            url: URL(string: "https://zoom.us/j/5551112222"),
            organizer: nil,
            attendees: attendees,
            startDate: start,
            endDate: end,
            isAllDay: false,
            recurrent: false,
            calendar: MBCalendar(
                title: "Work",
                id: "work",
                source: "Google",
                email: nil,
                color: .black
            )
        )

        let appleEvent = createAppleScriptEvent(event: event, type: .meetingStart)
        let parameters = appleEvent.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))

        XCTAssertEqual(
            appleEvent.paramDescriptor(forKeyword: AEKeyword(keyASSubroutineName))?.stringValue,
            ScriptType.meetingStart.rawValue
        )
        XCTAssertEqual(parameters?.atIndex(1)?.stringValue, event.scriptIdentifier)
        XCTAssertEqual(parameters?.atIndex(2)?.stringValue, event.title)
        XCTAssertEqual(parameters?.atIndex(3)?.booleanValue, event.isAllDay)
        XCTAssertEqual(parameters?.atIndex(4)?.dateValue, start)
        XCTAssertEqual(parameters?.atIndex(5)?.dateValue, end)
        XCTAssertEqual(parameters?.atIndex(6)?.stringValue, event.location)
        XCTAssertEqual(parameters?.atIndex(8)?.int32Value, 2)
        XCTAssertEqual(parameters?.atIndex(9)?.stringValue, event.meetingLink?.url.absoluteString)
        XCTAssertEqual(parameters?.atIndex(10)?.stringValue, MeetingServices.zoom.rawValue)
        XCTAssertEqual(parameters?.atIndex(11)?.stringValue, event.notes)
    }

    func testCreateAppleScriptParametersHandlesCustomMeetingService() {
        var event = makeFakeEvent(
            id: "custom-service",
            start: Date(),
            end: Date().addingTimeInterval(1800)
        )
        event.meetingLink = MeetingLink(
            service: nil,
            url: URL(string: "https://meetings.example.com/custom-room")!
        )

        let parameters = createAppleScriptParametersForEvent(event: event)

        XCTAssertEqual(parameters.atIndex(9)?.stringValue, event.meetingLink?.url.absoluteString)
        XCTAssertEqual(parameters.atIndex(10)?.stringValue, "EMPTY")
    }
}
