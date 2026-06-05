//
//  StatusTab.swift
//  MeetingBar
//

import SwiftUI

struct StatusTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            GroupBox(label: Label("preferences_status_provider_status_title".loco(), systemImage: "antenna.radiowaves.left.and.right")) {
                ProviderStatusSection()
            }
            GroupBox(label: Label("preferences_status_permissions_title".loco(), systemImage: "checkmark.shield")) {
                PermissionsSection()
            }
            GroupBox(label: Label("preferences_status_diagnostics_title".loco(), systemImage: "doc.on.clipboard")) {
                DiagnosticsSection()
            }
            Spacer()
        }
    }
}

private struct ProviderStatusSection: View {
    @EnvironmentObject var calendarSync: CalendarSync

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                Spacer()
                Button("preferences_status_refresh_now".loco()) {
                    Task { try? await calendarSync.refreshSources() }
                }
            }

            if let lastSuccess = calendarSync.providerHealth.lastSuccessfulRefresh {
                HStack {
                    Text("preferences_status_last_successful_refresh".loco())
                        .foregroundStyle(.secondary)
                    Text(lastSuccess.formatted(date: .omitted, time: .shortened))
                }
            }

            if let error = calendarSync.providerHealth.lastErrorDescription {
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
        let health = calendarSync.providerHealth
        if health.authRequired { return .red }
        if health.lastErrorDescription != nil { return .red }
        if health.isStale { return .orange }
        if health.lastSuccessfulRefresh != nil { return .green }
        return .gray
    }

    private var statusText: String {
        let health = calendarSync.providerHealth
        if health.authRequired { return "preferences_status_state_auth_required".loco() }
        if health.lastErrorDescription != nil { return "preferences_status_state_error".loco() }
        if health.isStale { return "preferences_status_state_stale".loco() }
        if health.lastSuccessfulRefresh != nil { return "preferences_status_state_ok".loco() }
        return "preferences_status_state_initializing".loco()
    }
}

private struct PermissionsSection: View {
    @State private var snapshot: PermissionSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snap = snapshot {
                PermissionRow(
                    label: "preferences_status_permission_calendar".loco(),
                    ok: snap.calendarAccess == .authorized,
                    detail: calendarDetail(snap.calendarAccess)
                )
                PermissionRow(
                    label: "preferences_status_permission_notifications".loco(),
                    ok: snap.notificationAccess == .authorized || snap.notificationAccess == .provisional,
                    detail: notificationDetail(snap.notificationAccess)
                )
                if snap.googleAuthStatus != .notActive {
                    PermissionRow(
                        label: "preferences_status_permission_google".loco(),
                        ok: snap.googleAuthStatus == .authorized,
                        detail: snap.googleAuthStatus == .authorized
                            ? "preferences_status_permission_authorized".loco()
                            : "preferences_status_permission_not_authorized".loco()
                    )
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .task {
            let provider = AppSettings.current.calendar.eventStoreProvider
            snapshot = await PermissionReporter.current(provider: provider)
        }
    }

    private func calendarDetail(_ access: PermissionSnapshot.CalendarAccess) -> String {
        switch access {
        case .authorized: return "preferences_status_permission_authorized".loco()
        case .denied: return "preferences_status_permission_denied".loco()
        case .restricted: return "preferences_status_permission_restricted".loco()
        case .notDetermined: return "preferences_status_permission_not_determined".loco()
        }
    }

    private func notificationDetail(_ access: PermissionSnapshot.NotificationAccess) -> String {
        switch access {
        case .authorized: return "preferences_status_permission_authorized".loco()
        case .provisional: return "preferences_status_permission_provisional".loco()
        case .denied: return "preferences_status_permission_denied".loco()
        case .notDetermined: return "preferences_status_permission_not_determined".loco()
        }
    }
}

private struct PermissionRow: View {
    let label: String
    let ok: Bool
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(label)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

private struct DiagnosticsSection: View {
    @EnvironmentObject var calendarSync: CalendarSync

    var body: some View {
        HStack(alignment: .top) {
            Text("preferences_status_diagnostics_hint".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("preferences_status_copy_diagnostics".loco()) {
                DiagnosticsClipboard.copy(calendarSync: calendarSync)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
}
