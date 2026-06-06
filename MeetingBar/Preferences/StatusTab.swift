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
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        let presentation = PreferencesCalendarPresentation.make(from: appModel.state)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(presentation.statusTone))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.providerTitleKey.loco())
                        .font(.headline)
                    Text(presentation.statusTextKey.loco())
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
                if presentation.canReconnect {
                    Button("preferences_status_reconnect".loco()) {
                        appModel.send(.changeProvider(presentation.activeProvider, signOut: true))
                    }
                    .disabled(appModel.state.providerChangeInProgress)
                }
                if presentation.canOpenCalendarSettings {
                    Button("preferences_status_open_calendar_settings".loco()) {
                        NSWorkspace.shared.open(Links.calendarPreferences)
                    }
                }
                Button("preferences_status_refresh_now".loco()) {
                    appModel.send(.refreshCalendars)
                }
            }

            if let lastSuccess = appModel.state.providerHealth.lastSuccessfulRefresh {
                HStack {
                    Text("preferences_status_last_successful_refresh".loco())
                        .foregroundStyle(.secondary)
                    Text(lastSuccess.formatted(date: .omitted, time: .shortened))
                }
            }

            if let error = appModel.state.providerHealth.lastErrorDescription {
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

    private func statusColor(_ tone: PreferencesStatusTone) -> Color {
        switch tone {
        case .neutral: .gray
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

private struct PermissionsSection: View {
    @EnvironmentObject var appModel: AppModel
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
        .task(id: appModel.state.activeProvider) {
            snapshot = await PermissionReporter.current(provider: appModel.state.activeProvider)
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
