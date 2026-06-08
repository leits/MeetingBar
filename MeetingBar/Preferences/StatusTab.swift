//
//  StatusTab.swift
//  MeetingBar
//

import SwiftUI

struct StatusTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(
                label: Label(
                    "preferences_status_permissions_title".loco(),
                    systemImage: "checkmark.shield")
            ) {
                PermissionsSection()
            }
            GroupBox(
                label: Label(
                    "preferences_status_diagnostics_title".loco(),
                    systemImage: "doc.on.clipboard")
            ) {
                DiagnosticsSection()
            }
            Spacer()
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
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        HStack(alignment: .top) {
            Text("preferences_status_diagnostics_hint".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("preferences_status_copy_diagnostics".loco()) {
                DiagnosticsClipboard.copy(
                    snapshot: DiagnosticsSnapshot(appState: appModel.state)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
}
