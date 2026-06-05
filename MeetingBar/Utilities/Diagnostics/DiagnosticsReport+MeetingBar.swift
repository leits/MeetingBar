//
//  DiagnosticsReport+MeetingBar.swift
//  MeetingBar
//

import AppKit
import Foundation

extension DiagnosticsProvider {
    init(provider: EventStoreProvider) {
        switch provider {
        case .macOSEventKit:
            self = .macOSEventKit
        case .googleCalendar:
            self = .googleCalendar
        }
    }
}

extension DiagnosticsHealth {
    init(health: ProviderHealth) {
        self.init(
            lastSuccessfulRefresh: health.lastSuccessfulRefresh,
            lastAttemptedRefresh: health.lastAttemptedRefresh,
            lastErrorDescription: health.lastErrorDescription,
            isStale: health.isStale,
            authRequired: health.authRequired
        )
    }
}

extension DiagnosticsContext {
    init(
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        provider: EventStoreProvider,
        selectedCalendarCount: Int,
        totalCalendarCount: Int,
        visibleEventCount: Int,
        health: ProviderHealth,
        permissions: PermissionSnapshot? = nil
    ) {
        self.init(
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            provider: DiagnosticsProvider(provider: provider),
            selectedCalendarCount: selectedCalendarCount,
            totalCalendarCount: totalCalendarCount,
            visibleEventCount: visibleEventCount,
            health: DiagnosticsHealth(health: health),
            permissions: permissions
        )
    }

    /// Snapshot of everything the issue-report formatter needs, drawn from
    /// the bundle, the running OS, the current settings, and the live
    /// `CalendarSync`. Use from any view that wants to show or export
    /// diagnostics — `StatusTab`, future onboarding error states, etc.
    @MainActor
    static func current(calendarSync: CalendarSync) async -> DiagnosticsContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let settings = AppSettings.current
        let permissions = await PermissionReporter.current(provider: settings.calendar.eventStoreProvider)
        return DiagnosticsContext(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: info["CFBundleVersion"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            provider: settings.calendar.eventStoreProvider,
            selectedCalendarCount: settings.calendar.selectedCalendarIDs.count,
            totalCalendarCount: calendarSync.calendars.count,
            visibleEventCount: calendarSync.events.count,
            health: calendarSync.providerHealth,
            permissions: permissions
        )
    }
}

@MainActor
enum DiagnosticsClipboard {
    /// Copies the formatted diagnostics report to the system pasteboard.
    /// Single entry point so views don't reach into NSPasteboard directly.
    static func copy(calendarSync: CalendarSync) {
        Task { @MainActor in
            let context = await DiagnosticsContext.current(calendarSync: calendarSync)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(DiagnosticsReport.text(from: context), forType: .string)
        }
    }
}
