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
                GroupBox(label: Label("Google Accounts", systemImage: "person.3")) {
                    GoogleAccountsSection(eventManager: eventManager)
                }
                .padding(.bottom, 5)
            }

            Label("preferences_calendars_select_calendars_title".loco(), systemImage: "calendar").padding(5)
            List {
                if eventManager.calendars.isEmpty {
                    if Defaults[.eventStoreProvider] == .macOSEventKit {
                        AccessDeniedBanner()
                    } else {
                        Text("No accounts connected. Add a Google account to get started.")
                            .foregroundColor(.secondary)
                            .padding()
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

struct GoogleAccountsSection: View {
    @ObservedObject var eventManager: EventManager
    @State private var accounts: [GoogleAccount] = []
    @State private var showingAddAccount = false
    @State private var accountToRemove: GoogleAccount?
    @State private var showingRemoveConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if accounts.isEmpty {
                Text("No Google accounts connected")
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
                        Text("Connected")
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
                    .help("Remove \(account.email)")
                }
                .padding(.vertical, 2)
            }

            Divider()

            Button(action: {
                showingAddAccount = true
            }) {
                Label("Add Google Account", systemImage: "plus.circle.fill")
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountSheet(onAccountAdded: {
                    Task {
                        await refreshAccounts()
                        try? await eventManager.refreshSources()
                    }
                })
            }
        }
        .padding(5)
        .onAppear {
            Task { await refreshAccounts() }
        }
        .onChange(of: Defaults[.googleAccounts]) { _ in
            Task { await refreshAccounts() }
        }
        .confirmationDialog(
            "Remove Account",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible,
            presenting: accountToRemove
        ) { account in
            Button("Remove \(account.email)", role: .destructive) {
                Task {
                    await GCEventStore.shared.removeAccount(account)
                    await refreshAccounts()
                    try? await eventManager.refreshSources()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text("This will remove \(account.email) and all its calendars from MeetingBar. You can add it back later.")
        }
    }

    private func refreshAccounts() async {
        await MainActor.run {
            accounts = Defaults[.googleAccounts]
        }
    }
}

struct AddAccountSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var errorMessage: String?
    @State private var isAdding = false
    var onAccountAdded: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Google Account")
                .font(.headline)

            Text("You'll be redirected to Google to sign in and grant calendar access.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if isAdding {
                ProgressView("Waiting for authentication...")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: {
                    Task {
                        isAdding = true
                        do {
                            _ = try await GCEventStore.shared.addAccount()
                            onAccountAdded()
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
                        Text("Sign in with Google")
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
                Text("access_screen_provider_macos_title".loco()).tag(EventStoreProvider.macOSEventKit)
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
