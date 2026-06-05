//
//  DiagnosticsReport.swift
//  MeetingBar
//

import Foundation

enum DiagnosticsProvider: Equatable {
    case macOSEventKit
    case googleCalendar
}

struct DiagnosticsHealth: Equatable {
    let lastSuccessfulRefresh: Date?
    let lastAttemptedRefresh: Date?
    let lastErrorDescription: String?
    let isStale: Bool
    let authRequired: Bool

    init(
        lastSuccessfulRefresh: Date? = nil,
        lastAttemptedRefresh: Date? = nil,
        lastErrorDescription: String? = nil,
        isStale: Bool = false,
        authRequired: Bool = false
    ) {
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.lastAttemptedRefresh = lastAttemptedRefresh
        self.lastErrorDescription = lastErrorDescription
        self.isStale = isStale
        self.authRequired = authRequired
    }
}

/// Inputs needed to produce a plain-text diagnostics report. All fields are
/// captured by the caller so the formatter is pure and testable.
struct DiagnosticsContext {
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let provider: DiagnosticsProvider
    let selectedCalendarCount: Int
    let totalCalendarCount: Int
    let visibleEventCount: Int
    let health: DiagnosticsHealth
    let permissions: PermissionSnapshot?
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
        let staleData = context.health.isStale ? "yes" : "no"
        let authRequired = context.health.authRequired ? "yes" : "no"
        var lines = """
        MeetingBar \(context.appVersion) (\(context.buildNumber))
        macOS: \(context.osVersion)
        Provider: \(providerLabel(context.provider))
        Provider health: \(healthLabel(context.health))
        Stale data: \(staleData)
        Auth required: \(authRequired)
        Calendars: \(context.selectedCalendarCount) selected / \(context.totalCalendarCount) available
        Visible events: \(context.visibleEventCount)
        Last successful refresh: \(lastSuccess)
        Last attempted refresh: \(lastAttempt)
        Last error: \(lastError)
        """
        if let perms = context.permissions {
            lines += "\n" + permissionsLines(perms)
        }
        return lines
    }

    private static func permissionsLines(_ perms: PermissionSnapshot) -> String {
        let calendar: String
        switch perms.calendarAccess {
        case .authorized: calendar = "authorized"
        case .denied: calendar = "denied"
        case .restricted: calendar = "restricted"
        case .notDetermined: calendar = "not determined"
        }

        let notifications: String
        switch perms.notificationAccess {
        case .authorized: notifications = "authorized"
        case .denied: notifications = "denied"
        case .provisional: notifications = "provisional"
        case .notDetermined: notifications = "not determined"
        }

        let google: String
        switch perms.googleAuthStatus {
        case .notActive: google = "n/a"
        case .authorized: google = "authorized"
        case .notAuthorized: google = "not authorized"
        }

        let script = perms.scriptFileExists ? "found" : "not found"
        let source = perms.isAppStoreBuild ? "App Store" : "direct"
        return """
        Calendar permission: \(calendar)
        Notification permission: \(notifications)
        Google auth: \(google)
        Script file: \(script)
        App source: \(source)
        """
    }

    private static func providerLabel(_ provider: DiagnosticsProvider) -> String {
        switch provider {
        case .macOSEventKit: return "Calendar.app (EventKit)"
        case .googleCalendar: return "Google Calendar"
        }
    }

    private static func healthLabel(_ health: DiagnosticsHealth) -> String {
        if health.authRequired { return "auth required" }
        if health.lastErrorDescription != nil { return "error" }
        if health.isStale { return "stale" }
        if health.lastSuccessfulRefresh != nil { return "ok" }
        return "initializing"
    }
}
