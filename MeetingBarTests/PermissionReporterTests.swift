import EventKit
import XCTest

@testable import MeetingBar

final class PermissionReporterTests: XCTestCase {
    func testCalendarPermissionMappingPreservesNonReadableStates() {
        XCTAssertEqual(PermissionReporter.calendarAccess(for: .notDetermined), .notDetermined)
        XCTAssertEqual(PermissionReporter.calendarAccess(for: .restricted), .restricted)
        XCTAssertEqual(PermissionReporter.calendarAccess(for: .denied), .denied)
    }

    func testFullAccessAndWriteOnlyHaveDifferentDiagnostics() {
        if #available(macOS 14, *) {
            XCTAssertEqual(PermissionReporter.calendarAccess(for: .fullAccess), .authorized)
            XCTAssertEqual(PermissionReporter.calendarAccess(for: .writeOnly), .writeOnly)
        } else {
            XCTAssertEqual(PermissionReporter.calendarAccess(for: .authorized), .authorized)
        }
    }
}
