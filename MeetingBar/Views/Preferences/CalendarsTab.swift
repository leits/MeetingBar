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
    @State var calendarsBySource: [String: [MBCalendar]] = [:]
    @State var showingAddAcountModal = false

    let appDelegate = NSApplication.shared.delegate as! AppDelegate?

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Default(.selectedCalendarIDs) var selectedCalendarIDs
    @Default(.eventStoreProvider) var eventStoreProvider

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("preferences_calendars_select_calendars_title".loco())
                Spacer()
            }
            VStack(spacing: 15) {
                Form {
                    List {
                        ForEach(Array(self.calendarsBySource.keys), id: \.self) { source in
                            Section(header: Text(source)) {
                                ForEach(self.calendarsBySource[source]!, id: \.ID) { calendar in
                                    CalendarRow(title: calendar.title, isSelected: self.selectedCalendarIDs.contains(calendar.ID), color: Color(calendar.color)) {
                                        if self.selectedCalendarIDs.contains(calendar.ID) {
                                            self.selectedCalendarIDs.removeAll { $0 == calendar.ID }
                                        } else {
                                            self.selectedCalendarIDs.append(calendar.ID)
                                        }
                                    }
                                }
                            }
                        }
                    }.listStyle(SidebarListStyle())
                }
            }.border(Color.gray)
            Divider()

            VStack(alignment: .leading) {
                HStack {
                    Text("preferences_calendars_provider_section_title".loco()).font(.headline).bold()
                }
                HStack {
                    if eventStoreProvider == .GoogleCalendar {
                        Text("Google Calendar API")
                        Button("preferences_calendars_provider_gcalendar_change_account".loco()) {
                            _ = appDelegate!.eventStore.signOut().done {
                                changeEventStoreProvider(.GoogleCalendar)
                            }
                        }
                        Spacer()

                        Button("preferences_calendars_provider_macos_switch".loco()) { changeEventStoreProvider(.MacOSEventKit) }
                    } else if eventStoreProvider == .MacOSEventKit {
                        Text("access_screen_provider_macos_title".loco())
                        Button("preferences_calendars_add_account_button".loco()) { self.showingAddAcountModal.toggle() }
                            .sheet(isPresented: $showingAddAcountModal) {
                                AddAccountModal()
                            }
                        Spacer()
                        Button("preferences_calendars_provider_gcalendar_switch".loco()) { changeEventStoreProvider(.GoogleCalendar) }
                    }
                }.padding(.horizontal, 10)
            }
        }.onReceive(timer) { _ in loadCalendarList() }
        .onDisappear { timer.upstream.connect().cancel() }
        .padding()
    }

    func changeEventStoreProvider(_ provider: eventStoreProvider) {
        selectedCalendarIDs = []
        appDelegate!.statusBarItem.calendars = []
        appDelegate!.statusBarItem.events = []

        appDelegate!.setEventStoreProvider(provider: provider)

        _ = appDelegate!.eventStore.signIn().done {
            DispatchQueue.main.async {
                appDelegate!.statusBarItem.loadCalendars()
            }
        }
    }

    func loadCalendarList() {
        calendarsBySource = Dictionary(grouping: appDelegate!.statusBarItem.calendars) { $0.source }
    }
}

struct AddAccountModal: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading) {
                Text("preferences_calendars_add_account_modal".loco())
            }
            Spacer()
            HStack {
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("general_close".loco())
                }
            }
        }.padding().frame(width: 400, height: 200)
    }
}

struct CalendarRow: View {
    var title: String
    var isSelected: Bool
    var color: Color
    var action: () -> Void

    var body: some View {
        HStack {
            Button(action: self.action) {
                Section {
                    if self.isSelected {
                        Image(nsImage: NSImage(named: NSImage.menuOnStateTemplateName)!)
                    } else {
                        Image(nsImage: NSImage(named: NSImage.addTemplateName)!)
                    }
                }.frame(width: 20, height: 17)
            }
            Circle().fill(self.color).frame(width: 8, height: 8)
            Text(self.title)
        }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }
}
