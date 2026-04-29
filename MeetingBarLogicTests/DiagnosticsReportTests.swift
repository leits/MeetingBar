//
//  DiagnosticsReportTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class DiagnosticsReportTests: XCTestCase {
    private let knownDate = Date(timeIntervalSince1970: 1_730_000_000)

    private func context(
        provider: DiagnosticsProvider = .macOSEventKit,
        health: DiagnosticsHealth = DiagnosticsHealth()
    ) -> DiagnosticsContext {
        DiagnosticsContext(
            appVersion: "4.12",
            buildNumber: "999",
            osVersion: "Version 14.5 (Build 23F79)",
            provider: provider,
            selectedCalendarCount: 3,
            totalCalendarCount: 7,
            visibleEventCount: 5,
            health: health
        )
    }

    func testReportHeaderIncludesVersionsAndProvider() {
        let report = DiagnosticsReport.text(from: context())

        XCTAssertTrue(report.contains("MeetingBar 4.12 (999)"))
        XCTAssertTrue(report.contains("macOS: Version 14.5 (Build 23F79)"))
        XCTAssertTrue(report.contains("Provider: Calendar.app (EventKit)"))
    }

    func testReportLabelsGoogleCalendarProvider() {
        let report = DiagnosticsReport.text(from: context(provider: .googleCalendar))
        XCTAssertTrue(report.contains("Provider: Google Calendar"))
    }

    func testReportShowsCalendarAndEventCounts() {
        let report = DiagnosticsReport.text(from: context())
        XCTAssertTrue(report.contains("Calendars: 3 selected / 7 available"))
        XCTAssertTrue(report.contains("Visible events: 5"))
    }

    func testReportEmitsNeverWhenNoRefreshAttempted() {
        let report = DiagnosticsReport.text(from: context(health: DiagnosticsHealth()))

        XCTAssertTrue(report.contains("Provider health: initializing"))
        XCTAssertTrue(report.contains("Stale data: no"))
        XCTAssertTrue(report.contains("Auth required: no"))
        XCTAssertTrue(report.contains("Last successful refresh: never"))
        XCTAssertTrue(report.contains("Last attempted refresh: never"))
        XCTAssertTrue(report.contains("Last error: none"))
    }

    func testReportFormatsDatesAsISO8601() {
        let health = DiagnosticsHealth(
            lastSuccessfulRefresh: knownDate,
            lastAttemptedRefresh: knownDate,
            lastErrorDescription: nil,
            isStale: false
        )
        let report = DiagnosticsReport.text(from: context(health: health))

        // ISO-8601 representation of 1_730_000_000 in UTC.
        let formatter = ISO8601DateFormatter()
        let expected = formatter.string(from: knownDate)
        XCTAssertTrue(report.contains("Last successful refresh: \(expected)"))
        XCTAssertTrue(report.contains("Last attempted refresh: \(expected)"))
    }

    func testReportShowsOKHealthWhenRefreshSucceeded() {
        let health = DiagnosticsHealth(
            lastSuccessfulRefresh: knownDate,
            lastAttemptedRefresh: knownDate,
            lastErrorDescription: nil,
            isStale: false,
            authRequired: false
        )
        let report = DiagnosticsReport.text(from: context(health: health))

        XCTAssertTrue(report.contains("Provider health: ok"))
        XCTAssertTrue(report.contains("Stale data: no"))
        XCTAssertTrue(report.contains("Auth required: no"))
    }

    func testReportShowsErrorDescriptionWhenPresent() {
        let health = DiagnosticsHealth(
            lastSuccessfulRefresh: knownDate.addingTimeInterval(-3600),
            lastAttemptedRefresh: knownDate,
            lastErrorDescription: "The Internet connection appears to be offline.",
            isStale: true
        )
        let report = DiagnosticsReport.text(from: context(health: health))
        XCTAssertTrue(report.contains("Provider health: error"))
        XCTAssertTrue(report.contains("Stale data: yes"))
        XCTAssertTrue(report.contains("Auth required: no"))
        XCTAssertTrue(report.contains("Last error: The Internet connection appears to be offline."))
    }

    func testReportShowsAuthRequiredState() {
        let health = DiagnosticsHealth(
            lastSuccessfulRefresh: knownDate.addingTimeInterval(-3600),
            lastAttemptedRefresh: knownDate,
            lastErrorDescription: "Google Calendar authorization is required",
            isStale: true,
            authRequired: true
        )
        let report = DiagnosticsReport.text(from: context(health: health))

        XCTAssertTrue(report.contains("Provider health: auth required"))
        XCTAssertTrue(report.contains("Stale data: yes"))
        XCTAssertTrue(report.contains("Auth required: yes"))
    }
}
