//
//  CalendarsTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI
import EventKit

import Defaults

struct CalendarsTab: View {
    @State var calendarsBySource: [String: [EKCalendar]] = [:]
    @State var showingAddAcountModal = false

    @Default(.selectedCalendarIDs) var selectedCalendarIDs

    var body: some View {
        VStack {
            HStack {
                Text("preferences_calendars_select_calendars_title".loco())
                Spacer()
                Button(action: self.loadCalendarList) {
                    Image(nsImage: NSImage(named: NSImage.refreshTemplateName)!)
                }
            }
            VStack(alignment: .leading, spacing: 15) {
                Form {
                    Section {
                        List {
                            ForEach(Array(calendarsBySource.keys), id: \.self) { source in
                                Section(header: Text(source)) {
                                    ForEach(self.calendarsBySource[source]!, id: \.self) { calendar in
                                        CalendarRow(title: calendar.title, isSelected: self.selectedCalendarIDs.contains(calendar.calendarIdentifier), color: Color(calendar.color)) {
                                            if self.selectedCalendarIDs.contains(calendar.calendarIdentifier) {
                                                self.selectedCalendarIDs.removeAll { $0 == calendar.calendarIdentifier }
                                            } else {
                                                self.selectedCalendarIDs.append(calendar.calendarIdentifier)
                                            }
                                        }
                                    }
                                }
                            }
                        }.listStyle(SidebarListStyle())
                    }
                }
            }.border(Color.gray)
            HStack {
                Text("preferences_calendars_add_account_description".loco())
                Button("preferences_calendars_add_account_button".loco()) { self.showingAddAcountModal.toggle() }
                    .sheet(isPresented: $showingAddAcountModal) {
                        AddAccountModal()
                    }
                Spacer()
            }
        }.onAppear { self.loadCalendarList() }.padding()
    }

    func loadCalendarList() {
        if let app = NSApplication.shared.delegate as! AppDelegate? {
            calendarsBySource = app.statusBarItem.eventStore.getAllCalendars()
        }
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
