//
//  CalendarsTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import EventKit
import SwiftUI

import Defaults

struct CalendarsTab: View {
    @ObservedObject var eventManager: EventManager

    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Label("Data Source", systemImage: "server.rack")) {
                ProviderPicker(eventManager: eventManager)
            }
            .padding(.bottom, 5)
            Label("preferences_calendars_select_calendars_title".loco(), systemImage: "calendar").padding(5)
            List {
                if eventManager.calendars.isEmpty {
                    if Defaults[.eventStoreProvider] == .macOSEventKit {
                        AccessDeniedBanner()
                    }
                    Button("Refresh") {
                        Task { try await eventManager.refreshSources() }
                    }

                } else {
                    CalendarSectionsView(calendars: eventManager.calendars)
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
    @ObservedObject var eventManager: EventManager
    @State private var picker: EventStoreProvider = Defaults[.eventStoreProvider]

    var body: some View {
        HStack {
            Picker("", selection: $picker) {
                Text("access_screen_provider_macos_title".loco()).tag(EventStoreProvider.macOSEventKit)
                Text("Google Calendar API").tag(EventStoreProvider.googleCalendar)
            }
            .onChange(of: picker) { provider in
                Task { await eventManager.changeEventStoreProvider(provider) }
            }

            if Defaults[.eventStoreProvider] == .googleCalendar {
                Button("preferences_calendars_provider_gcalendar_change_account".loco()) {
                    Task {
                        await eventManager.changeEventStoreProvider(.googleCalendar, withSignOut: true)
                    }
                }
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
    var calendar: MBCalendar
    @State var isSelected: Bool

    init(calendar: MBCalendar) {
        self.calendar = calendar
        isSelected = Defaults[.selectedCalendarIDs].contains(calendar.id)
    }

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack {
                Text("")
                Circle().fill(Color(calendar.color)).frame(width: 10, height: 10)
                Text(calendar.title)
            }
        }
        .onAppear {
            isSelected = Defaults[.selectedCalendarIDs].contains(calendar.id)
        }
        .onChange(of: isSelected) { newValue in
            if newValue {
                Defaults[.selectedCalendarIDs].append(calendar.id)
            } else {
                Defaults[.selectedCalendarIDs].removeAll { $0 == calendar.id }
            }
            Defaults[.selectedCalendarIDs] = Array(Set(Defaults[.selectedCalendarIDs])) // Deduplication
        }
    }
}

#Preview {
    List {
        CalendarSectionsView(calendars: [MBCalendar(title: "Calendar #1", id: "1", source: "Source #1", email: nil, color: .brown)])

        CalendarSectionsView(calendars: [MBCalendar(title: "Calendar #2", id: "2", source: "Source #2", email: nil, color: .blue)])
    }.listStyle(.sidebar)
        .frame(width: 300, height: 200)
}
