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
        health: ProviderHealth
    ) {
        self.init(
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            provider: DiagnosticsProvider(provider: provider),
            selectedCalendarCount: selectedCalendarCount,
            totalCalendarCount: totalCalendarCount,
            visibleEventCount: visibleEventCount,
            health: DiagnosticsHealth(health: health)
        )
    }

    /// Snapshot of everything the issue-report formatter needs, drawn from
    /// the bundle, the running OS, the current settings, and the live
    /// `EventManager`. Use from any view that wants to show or export
    /// diagnostics — `StatusTab`, future onboarding error states, etc.
    @MainActor
    static func current(eventManager: EventManager) -> DiagnosticsContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let settings = AppSettings.current
        return DiagnosticsContext(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: info["CFBundleVersion"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            provider: settings.calendar.eventStoreProvider,
            selectedCalendarCount: settings.calendar.selectedCalendarIDs.count,
            totalCalendarCount: eventManager.calendars.count,
            visibleEventCount: eventManager.events.count,
            health: eventManager.providerHealth
        )
    }
}

@MainActor
enum DiagnosticsClipboard {
    /// Copies the formatted diagnostics report to the system pasteboard.
    /// Single entry point so views don't reach into NSPasteboard directly.
    static func copy(eventManager: EventManager) {
        let context = DiagnosticsContext.current(eventManager: eventManager)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DiagnosticsReport.text(from: context), forType: .string)
    }
}
