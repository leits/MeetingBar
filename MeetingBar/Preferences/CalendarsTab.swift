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
        VStack(alignment: .leading) {
            GroupBox(
                label: Label(
                    "preferences_section_data_source_title".loco(), systemImage: "server.rack")
            ) {
                ProviderPicker()
            }
            .padding(.bottom, 5)
            Label("preferences_calendars_select_calendars_title".loco(), systemImage: "calendar")
                .padding(5)
            List {
                if appModel.state.calendars.isEmpty {
                    if appModel.state.activeProvider == .macOSEventKit {
                        AccessDeniedBanner()
                    }
                    Button("general_refresh".loco()) {
                        appModel.send(.refreshCalendars)
                    }

                } else {
                    CalendarSectionsView(calendars: appModel.state.calendars)
                }
            }
            .listStyle(.sidebar)
        }
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
                guard provider != appModel.state.activeProvider,
                      !appModel.state.providerChangeInProgress
                else { return }
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
            if !inProgress {
                picker = appModel.state.activeProvider
            }
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
    @Default(.selectedCalendarIDs) private var selectedIDs

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { selectedIDs.contains(calendar.id) },
                set: { appModel.toggleCalendarSelection(id: calendar.id, selected: $0) }
            )
        ) {
            HStack {
                Text("")
                Circle().fill(Color(calendar.color)).frame(width: 10, height: 10)
                Text(calendar.title)
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
