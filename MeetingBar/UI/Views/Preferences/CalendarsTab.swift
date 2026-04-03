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

            if Defaults[.eventStoreProvider] == .googleCalendar {
                GroupBox(label: Label("preferences_calendars_google_accounts_title", systemImage: "person.3")) {
                    GoogleAccountsSection(eventManager: eventManager)
                }
                .padding(.bottom, 5)
            }

            Label("preferences_calendars_select_calendars_title", systemImage: "calendar").padding(5)
            List {
                if eventManager.calendars.isEmpty {
                    if Defaults[.eventStoreProvider] == .macOSEventKit {
                        AccessDeniedBanner()
                    } else if Defaults[.googleAccounts].isEmpty {
                        Text("preferences_calendars_no_accounts_connected")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        Text("preferences_calendars_no_calendars_available")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    Button("preferences_calendars_refresh") {
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

struct GoogleAccountsSection: View {
    @ObservedObject var eventManager: EventManager
    @Default(.googleAccounts) private var accounts
    @State private var showingAddAccount = false
    @State private var accountToRemove: GoogleAccount?
    @State private var showingRemoveConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if accounts.isEmpty {
                Text("preferences_calendars_no_google_accounts_connected")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            ForEach(accounts) { account in
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text(account.email)
                            .font(.system(size: 13))
                        Text("preferences_calendars_account_connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        accountToRemove = account
                        showingRemoveConfirmation = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("preferences_calendars_remove_account_help")
                    .accessibilityLabel("preferences_calendars_remove_account_label")
                }
                .padding(.vertical, 2)
            }

            Divider()

            Button(action: {
                showingAddAccount = true
            }) {
                Label("preferences_calendars_add_google_account", systemImage: "plus.circle.fill")
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountSheet(onAccountAdded: {
                    Task {
                        try? await eventManager.refreshSources()
                    }
                })
            }
        }
        .padding(5)
        .confirmationDialog(
            "preferences_calendars_remove_account_dialog_title",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible,
            presenting: accountToRemove
        ) { account in
            Button("preferences_calendars_remove_account_action", role: .destructive) {
                Task {
                    await GCEventStore.shared.removeAccount(account)
                    try? await eventManager.refreshSources()
                }
            }
            Button("preferences_calendars_cancel", role: .cancel) {}
        } message: { _ in
            Text("preferences_calendars_remove_account_message")
        }
    }
}

struct AddAccountSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var errorMessage: String?
    @State private var isAdding = false
    var onAccountAdded: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("preferences_calendars_add_google_account_sheet_title")
                .font(.headline)

            Text("preferences_calendars_add_google_account_sheet_description")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if isAdding {
                ProgressView("preferences_calendars_waiting_for_authentication")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 12) {
                Button("preferences_calendars_cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: {
                    Task {
                        isAdding = true
                        do {
                            _ = try await GCEventStore.shared.addAccount()
                            await onAccountAdded()
                            presentationMode.wrappedValue.dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isAdding = false
                        }
                    }
                }) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Text("preferences_calendars_sign_in_with_google")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAdding)
            }
        }
        .padding()
        .frame(width: 320, height: 180)
    }
}

struct CalendarSectionsView: View {
    let calendars: [MBCalendar]

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
                Text("access_screen_provider_macos_title").tag(EventStoreProvider.macOSEventKit)
                Text("Google Calendar API").tag(EventStoreProvider.googleCalendar)
            }
            .onChange(of: picker) { provider in
                Task { await eventManager.changeEventStoreProvider(provider) }
            }
        }
    }
}

struct AccessDeniedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("access_screen_access_screen_access_denied_go_to_title")
            Button("access_screen_access_denied_system_preferences_button") {
                NSWorkspace.shared.open(Links.calendarPreferences)
            }
            Text("access_screen_access_denied_relaunch_title")
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
            Defaults[.selectedCalendarIDs] = Array(Set(Defaults[.selectedCalendarIDs]))
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
