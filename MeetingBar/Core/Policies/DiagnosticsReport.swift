//
//  DiagnosticsReport.swift
//  MeetingBar
//

import Foundation

/// Inputs needed to produce a plain-text diagnostics report. All fields are
/// captured by the caller so the formatter is pure and testable.
struct DiagnosticsContext {
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let provider: EventStoreProvider
    let selectedCalendarCount: Int
    let totalCalendarCount: Int
    let visibleEventCount: Int
    let health: ProviderHealth
}

enum DiagnosticsReport {
    /// Renders a multi-line plain-text report suitable for pasting into a
    /// GitHub issue. Dates are emitted in ISO-8601 so they are unambiguous
    /// across locales; missing values become "never" / "none".
    static func text(from context: DiagnosticsContext) -> String {
        let formatter = ISO8601DateFormatter()
        let lastSuccess = context.health.lastSuccessfulRefresh.map(formatter.string) ?? "never"
        let lastAttempt = context.health.lastAttemptedRefresh.map(formatter.string) ?? "never"
        let lastError = context.health.lastErrorDescription ?? "none"
        return """
        MeetingBar \(context.appVersion) (\(context.buildNumber))
        macOS: \(context.osVersion)
        Provider: \(providerLabel(context.provider))
        Calendars: \(context.selectedCalendarCount) selected / \(context.totalCalendarCount) available
        Visible events: \(context.visibleEventCount)
        Last successful refresh: \(lastSuccess)
        Last attempted refresh: \(lastAttempt)
        Last error: \(lastError)
        """
    }

    private static func providerLabel(_ provider: EventStoreProvider) -> String {
        switch provider {
        case .macOSEventKit: return "Calendar.app (EventKit)"
        case .googleCalendar: return "Google Calendar"
        }
    }
}
