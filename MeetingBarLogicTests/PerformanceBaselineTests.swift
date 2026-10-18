import Foundation
import XCTest

@testable import MeetingBarLogic

/// Opt-in reproducible workloads, never absolute latency gates on CI hardware.
final class PerformanceBaselineTests: XCTestCase {
    private func requirePerformanceMode() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MEETINGBAR_PERF_TESTS"] == "1",
            "Run opt-in benchmarks with make test-performance"
        )
    }

    func testLongMeetingDescriptionLinkDetectionBaseline() throws {
        try requirePerformanceMode()
        let notes = String(repeating: "Meeting discussion items and context. ", count: 1_500)
            + " https://meet.google.com/abc-defg-hij"
        XCTAssertNotNil(MeetingLinkDetector.detect(
            location: nil, eventURL: nil, notes: notes,
            calendarEmail: nil, currentUserEmail: nil
        ))
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            _ = MeetingLinkDetector.detect(
                location: nil, eventURL: nil, notes: notes,
                calendarEmail: nil, currentUserEmail: nil
            )
        }
    }

    func testLargeNextMeetingSelectionBaseline() throws {
        try requirePerformanceMode()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let events: [EventSelectionEvent] = (0..<5_000).map { index in
            EventSelectionEvent(
                sourceIndex: index,
                id: "event-\(index)",
                lastModifiedDate: nil,
                startDate: now.addingTimeInterval(TimeInterval(300 + index * 20)),
                endDate: now.addingTimeInterval(TimeInterval(2_100 + index * 20)),
                isAllDay: false,
                hasMeetingLink: true,
                hasAttendees: true,
                status: .active,
                participationStatus: .active
            )
        }
        let settings = EventSelectionSettings(
            period: .todayAndTomorrow,
            includesPersonalEvents: true,
            dismissedEvents: [],
            requiresMeetingLinkForNonAllDayEvents: false,
            hidesPendingEvents: false,
            hidesTentativeEvents: false,
            ongoingEventVisibility: .hideImmediateAfter
        )
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            _ = EventSelection.nextEvent(from: events.reversed(), linkRequired: false, settings: settings, now: now)
        }
    }

    func testLargeNotificationPlanningBaseline() throws {
        try requirePerformanceMode()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let events: [NotificationPlanningEvent] = (0..<2_000).map { index in
            let start = now.addingTimeInterval(TimeInterval(600 + index * 90))
            return NotificationPlanningEvent(
                id: "event-\(index)",
                startDate: start,
                endDate: start.addingTimeInterval(1800),
                status: .active,
                participationStatus: .active,
                isAllDay: false,
                hasMeetingLink: true
            )
        }
        let settings = NotificationPlanningSettings(
            eventStart: .init(enabled: true, offset: 60),
            eventEnd: .init(enabled: true, offset: 300),
            fullscreen: .disabled,
            autoJoin: .disabled,
            scriptOnStart: .disabled,
            dismissedEventIDs: []
        )
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            _ = NotificationPlanner.plan(events: events, settings: settings, now: now)
        }
    }
}
