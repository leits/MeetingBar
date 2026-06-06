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
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(presentation.providerTitleKey.loco())
                                .font(.headline)
                            Label(
                                presentation.statusTextKey.loco(),
                                systemImage: statusSystemImage(presentation.statusTone)
                            )
                            .foregroundStyle(statusColor(presentation.statusTone))
                            .font(.caption)
                        }
                        Spacer()
                        ProviderPicker()
                    }

                    Text(
                        "preferences_calendars_selection_summary".loco(
                            presentation.selectedCalendarCount,
                            presentation.availableCalendarCount
                        )
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)

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
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Button("preferences_calendars_select_all".loco()) {
                            appModel.setAllCalendarSelections(selected: true)
                        }
                        .disabled(
                            appModel.state.calendars.isEmpty
                                || presentation.selectedCalendarCount
                                    >= presentation.availableCalendarCount
                        )
                        Button("preferences_calendars_deselect_all".loco()) {
                            appModel.setAllCalendarSelections(selected: false)
                        }
                        .disabled(appModel.state.selectedCalendarIDs.isEmpty)
                    }

                    List {
                        if appModel.state.calendars.isEmpty {
                            CalendarPreferencesEmptyState(presentation: presentation)
                        } else {
                            CalendarSectionsView(calendars: appModel.state.calendars)
                        }
                    }
                    .listStyle(.inset)
                }
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
            Picker("", selection: $picker) {
                Text("access_screen_provider_macos_title".loco()).tag(
                    EventStoreProvider.macOSEventKit)
                Text("Google Calendar API").tag(EventStoreProvider.googleCalendar)
            }
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
