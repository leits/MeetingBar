//
//  CalendarsTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

struct CalendarsTab: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        let presentation = PreferencesCalendarPresentation.make(from: appModel.state)

        VStack(alignment: .leading, spacing: 12) {
            GroupBox(
                label: Label(
                    "preferences_calendar_source_title".loco(), systemImage: "server.rack")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ProviderPicker()

                    HStack(spacing: 6) {
                        Label(
                            presentation.statusTextKey.loco(),
                            systemImage: statusSystemImage(presentation.statusTone)
                        )
                        .foregroundStyle(statusColor(presentation.statusTone))
                        .font(.caption)
                        if let lastSuccess = appModel.state.providerHealth.lastSuccessfulRefresh {
                            Text("·")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                            Text(lastSuccess.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            presentation.providerDataSourceKey.loco(),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Label(
                            presentation.providerAccountScopeKey.loco(),
                            systemImage: "person.2"
                        )
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)

                    Text(
                        "preferences_calendars_selection_summary".loco(
                            presentation.selectedCalendarCount,
                            presentation.availableCalendarCount
                        )
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)

                    if let error = appModel.state.providerHealth.lastErrorDescription {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }

                    HStack {
                        if presentation.canReconnect {
                            Button("preferences_status_reconnect".loco()) {
                                appModel.send(
                                    .changeProvider(presentation.activeProvider, signOut: true))
                            }
                            .disabled(appModel.state.providerChangeInProgress)
                        }
                        if presentation.canOpenCalendarSettings {
                            Button("preferences_status_open_calendar_settings".loco()) {
                                NSWorkspace.shared.open(Links.calendarPreferences)
                            }
                        }
                        Button("general_refresh".loco()) {
                            appModel.send(.refreshCalendars)
                        }
                        .disabled(appModel.state.providerChangeInProgress)
                        Spacer()
                    }
                }
                .padding(8)
            }

            GroupBox(
                label: Label(
                    "preferences_calendars_select_calendars_title".loco(),
                    systemImage: "calendar")
            ) {
                List {
                    if appModel.state.calendars.isEmpty {
                        CalendarPreferencesEmptyState(presentation: presentation)
                    } else {
                        CalendarSectionsView(calendars: appModel.state.calendars)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 280)
            }

            GroupBox(
                label: Label(
                    "preferences_status_permissions_title".loco(),
                    systemImage: "checkmark.shield")
            ) {
                PermissionsSection()
            }
        }
    }

}

private struct CalendarPreferencesEmptyState: View {
    @EnvironmentObject var appModel: AppModel
    let presentation: PreferencesCalendarPresentation

    var body: some View {
        VStack(spacing: 10) {
            Text(emptyStateText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var emptyStateText: String {
        presentation.emptyStateTextKey.loco()
    }
}

struct PermissionsSection: View {
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

private func statusSystemImage(_ tone: PreferencesStatusTone) -> String {
    switch tone {
    case .neutral: "circle"
    case .success: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .error: "xmark.circle.fill"
    }
}

private func statusColor(_ tone: PreferencesStatusTone) -> Color {
    switch tone {
    case .neutral: .secondary
    case .success: .green
    case .warning: .orange
    case .error: .red
    }
}

struct CalendarSectionsView: View {
    let calendars: [MBCalendar]

    // 1. Compute once, with explicit types
    private var grouped: [String: [MBCalendar]] {
        Dictionary(grouping: calendars, by: \.source)
    }

    private var sources: [String] {
        grouped.keys.sorted()
    }

    var body: some View {
        ForEach(sources, id: \.self) { source in
            Section(header: Text(source)) {
                ForEach(grouped[source]!, id: \.id) { cal in
                    CalendarRow(calendar: cal)
                }
            }
        }
    }
}

struct ProviderPicker: View {
    @EnvironmentObject var appModel: AppModel
    @State private var picker = EventStoreProvider.macOSEventKit

    var body: some View {
        HStack {
            Picker("access_screen_provider_picker_label".loco(), selection: $picker) {
                ForEach(CalendarSourcePresentation.all) { source in
                    Text(source.titleKey.loco()).tag(source.provider)
                }
            }
            .labelsHidden()
            .onChange(of: picker) { provider in
                guard ProviderPickerSelectionPolicy.shouldRequestChange(
                    selectedProvider: provider,
                    activeProvider: appModel.state.activeProvider,
                    providerChangeInProgress: appModel.state.providerChangeInProgress
                ) else { return }
                appModel.send(.changeProvider(provider, signOut: false))
            }
            .disabled(appModel.state.providerChangeInProgress)

            if appModel.state.activeProvider == .googleCalendar {
                Button("preferences_calendars_provider_gcalendar_change_account".loco()) {
                    appModel.send(.changeProvider(.googleCalendar, signOut: true))
                }
                .disabled(appModel.state.providerChangeInProgress)
            }
        }
        .onAppear {
            picker = appModel.state.activeProvider
        }
        .onChange(of: appModel.state.activeProvider) { provider in
            picker = provider
        }
        .onChange(of: appModel.state.providerChangeInProgress) { inProgress in
            picker = ProviderPickerSelectionPolicy.synchronizedSelection(
                currentSelection: picker,
                activeProvider: appModel.state.activeProvider,
                providerChangeInProgress: inProgress
            )
        }
    }
}

struct AccessDeniedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("access_screen_access_screen_access_denied_go_to_title".loco())
            Button("access_screen_access_denied_system_preferences_button".loco()) {
                NSWorkspace.shared.open(Links.calendarPreferences)
            }
            Text("access_screen_access_denied_relaunch_title".loco())
        }
        .padding(.top, 8)
    }
}

struct CalendarRow: View {
    let calendar: MBCalendar
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { appModel.state.selectedCalendarIDs.contains(calendar.id) },
                set: { appModel.toggleCalendarSelection(id: calendar.id, selected: $0) }
            )
        ) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(calendar.color))
                    .frame(width: 10, height: 10)
                Text(calendar.title)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    List {
        CalendarSectionsView(calendars: [
            MBCalendar(
                title: "Calendar #1", id: "1", source: "Source #1", email: nil, color: .brown)
        ])

        CalendarSectionsView(calendars: [
            MBCalendar(title: "Calendar #2", id: "2", source: "Source #2", email: nil, color: .blue)
        ])
    }.listStyle(.sidebar)
        .frame(width: 300, height: 200)
}
