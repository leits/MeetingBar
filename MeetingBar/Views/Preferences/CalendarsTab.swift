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

    weak var appDelegate = NSApplication.shared.delegate as! AppDelegate?

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
                List {
                    ForEach(Array(self.calendarsBySource.keys), id: \.self) { source in
                        Section(header: Text(source)) {
                            ForEach(self.calendarsBySource[source]!, id: \.ID) { calendar in
                                CalendarRow(calendar: calendar)
                            }
                        }
                    }
                }.listStyle(SidebarListStyle())
            }
            Divider()

            VStack(alignment: .leading) {
                HStack {
                    Text("preferences_calendars_provider_section_title".loco()).font(.headline).bold()
                }
                HStack {
                    if eventStoreProvider == .googleCalendar {
                        Text("Google Calendar API")
                        Button("preferences_calendars_provider_gcalendar_change_account".loco()) {
                            _ = appDelegate!.eventStore.signOut().done {
                                changeEventStoreProvider(.googleCalendar)
                            }
                        }
                        Spacer()

                        Button("preferences_calendars_provider_macos_switch".loco()) { changeEventStoreProvider(.macOSEventKit) }
                    } else if eventStoreProvider == .macOSEventKit {
                        Text("access_screen_provider_macos_title".loco())
                        Button("preferences_calendars_add_account_button".loco()) { self.showingAddAcountModal.toggle() }
                            .sheet(isPresented: $showingAddAcountModal) {
                                AddAccountModal()
                            }
                        Spacer()
                        Button("preferences_calendars_provider_gcalendar_switch".loco()) { changeEventStoreProvider(.googleCalendar) }
                    }
                }.padding(.horizontal, 10)
            }
        }.padding()
            .onAppear {
                DispatchQueue.main.async {
                    appDelegate!.statusBarItem.loadCalendars()
                }
            }
            .onReceive(timer) { _ in loadCalendarList() }
            .onDisappear { timer.upstream.connect().cancel() }
    }

    func changeEventStoreProvider(_ provider: EventStoreProvider) {
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
    var calendar: MBCalendar
    @State var isSelected: Bool

    init(calendar: MBCalendar) {
        self.calendar = calendar
        isSelected = Defaults[.selectedCalendarIDs].contains(calendar.ID)
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
            isSelected = Defaults[.selectedCalendarIDs].contains(calendar.ID)
        }
        .onReceive([isSelected].publisher.first()) { newValue in
            if newValue {
                Defaults[.selectedCalendarIDs].append(calendar.ID)
            } else {
                Defaults[.selectedCalendarIDs].removeAll { $0 == calendar.ID }
            }
        }
    }
}
