//
//  StatusTab.swift
//  MeetingBar
//

import AppKit
import Defaults
import SwiftUI

struct StatusTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            GroupBox(label: Label("Provider Status", systemImage: "antenna.radiowaves.left.and.right")) {
                ProviderStatusSection()
            }
            GroupBox(label: Label("Diagnostics", systemImage: "doc.on.clipboard")) {
                DiagnosticsSection()
            }
            Spacer()
        }
    }
}

private struct ProviderStatusSection: View {
    @EnvironmentObject var eventManager: EventManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                Spacer()
                Button("preferences_status_refresh_now".loco()) {
                    Task { try? await eventManager.refreshSources() }
                }
            }

            if let lastSuccess = eventManager.providerHealth.lastSuccessfulRefresh {
                HStack {
                    Text("preferences_status_last_successful_refresh".loco())
                        .foregroundStyle(.secondary)
                    Text(lastSuccess.formatted(date: .omitted, time: .shortened))
                }
            }

            if let error = eventManager.providerHealth.lastErrorDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Text("preferences_status_last_error".loco())
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    private var statusColor: Color {
        let health = eventManager.providerHealth
        if health.lastErrorDescription != nil { return .red }
        if health.isStale { return .orange }
        if health.lastSuccessfulRefresh != nil { return .green }
        return .gray
    }

    private var statusText: String {
        let health = eventManager.providerHealth
        if health.lastErrorDescription != nil { return "preferences_status_state_error".loco() }
        if health.isStale { return "preferences_status_state_stale".loco() }
        if health.lastSuccessfulRefresh != nil { return "preferences_status_state_ok".loco() }
        return "preferences_status_state_initializing".loco()
    }
}

private struct DiagnosticsSection: View {
    @EnvironmentObject var eventManager: EventManager

    var body: some View {
        HStack(alignment: .top) {
            Text("preferences_status_diagnostics_hint".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("preferences_status_copy_diagnostics".loco()) {
                copyDiagnostics()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(buildDiagnosticsText(), forType: .string)
    }

    private func buildDiagnosticsText() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let appVersion = info["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = info["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let providerName: String
        switch Defaults[.eventStoreProvider] {
        case .macOSEventKit: providerName = "Calendar.app (EventKit)"
        case .googleCalendar: providerName = "Google Calendar"
        }
        let selectedCalendarCount = Defaults[.selectedCalendarIDs].count
        let totalCalendarCount = eventManager.calendars.count
        let visibleEventCount = eventManager.events.count
        let health = eventManager.providerHealth
        let formatter = ISO8601DateFormatter()
        let lastSuccess = health.lastSuccessfulRefresh.map(formatter.string) ?? "never"
        let lastAttempt = health.lastAttemptedRefresh.map(formatter.string) ?? "never"
        let lastError = health.lastErrorDescription ?? "none"
        return """
        MeetingBar \(appVersion) (\(buildNumber))
        macOS: \(osVersion)
        Provider: \(providerName)
        Calendars: \(selectedCalendarCount) selected / \(totalCalendarCount) available
        Visible events: \(visibleEventCount)
        Last successful refresh: \(lastSuccess)
        Last attempted refresh: \(lastAttempt)
        Last error: \(lastError)
        """
    }
}
