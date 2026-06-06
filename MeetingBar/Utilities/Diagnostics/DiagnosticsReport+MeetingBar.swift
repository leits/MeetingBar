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

struct DiagnosticsSnapshot: Equatable {
    let provider: EventStoreProvider
    let selectedCalendarCount: Int
    let totalCalendarCount: Int
    let visibleEventCount: Int
    let health: ProviderHealth

    init(appState: AppState) {
        provider = appState.activeProvider
        selectedCalendarCount = appState.selectedCalendarIDs.count
        totalCalendarCount = appState.calendars.count
        visibleEventCount = appState.events.count
        health = appState.providerHealth
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

    /// Adds platform metadata and permissions to the application-state
    /// snapshot used by the issue-report formatter.
    @MainActor
    static func current(snapshot: DiagnosticsSnapshot) async -> DiagnosticsContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let permissions = await PermissionReporter.current(provider: snapshot.provider)
        return DiagnosticsContext(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: info["CFBundleVersion"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            provider: snapshot.provider,
            selectedCalendarCount: snapshot.selectedCalendarCount,
            totalCalendarCount: snapshot.totalCalendarCount,
            visibleEventCount: snapshot.visibleEventCount,
            health: snapshot.health,
            permissions: permissions
        )
    }
}

@MainActor
enum DiagnosticsClipboard {
    /// Copies the formatted diagnostics report to the system pasteboard.
    /// Single entry point so views don't reach into NSPasteboard directly.
    static func copy(snapshot: DiagnosticsSnapshot) {
        Task { @MainActor in
            let context = await DiagnosticsContext.current(snapshot: snapshot)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(DiagnosticsReport.text(from: context), forType: .string)
        }
    }
}
