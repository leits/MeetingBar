//
//  PreferencesView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit
import SwiftUI

import Defaults
import KeyboardShortcuts

struct PreferencesView: View {
    var body: some View {
        VStack {
            TabView {
                General().tabItem { Text("General") }
                Appearance().tabItem { Text("Appearance") }
                Configuration().tabItem { Text("Services") }
                Calendars().padding().tabItem { Text("Calendars") }
            }
        }.padding()
    }
}

struct AboutApp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .center) {
                Spacer()
                Text("MeetingBar").font(.system(size: 20)).bold()
                if Bundle.main.infoDictionary != nil {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")").foregroundColor(.gray)
                }
                Spacer()
                Spacer()
                HStack {
                    Button("About this app", action: openAboutThisApp)
                    Spacer()
                    Button("Support the creator", action: openSupportTheCreator)
                }
            }
        }
    }

    func openAboutThisApp() {
        NSLog("Open AboutThisApp")
        _ = openLinkInDefaultBrowser(Links.aboutThisApp)
    }

    func openSupportTheCreator() {
        NSLog("Open SupportTheCreator")
        _ = openLinkInDefaultBrowser(Links.supportTheCreator)
    }
}

struct Calendars: View {
    @State var calendarsBySource: [String: [EKCalendar]] = [:]
    @State var showingAddAcountModal = false

    @Default(.selectedCalendarIDs) var selectedCalendarIDs

    var body: some View {
        VStack {
            HStack {
                Text("Select calendars to show events in status bar")
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
                                                self.selectedCalendarIDs.removeAll(where: { $0 == calendar.calendarIdentifier })
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
                Text("Don't see the calendar you need?")
                Button("Add account", action: { self.showingAddAcountModal.toggle() })
                    .sheet(isPresented: $showingAddAcountModal) {
                        AddAccountModal()
                    }
                Spacer()
            }
        }.onAppear { self.loadCalendarList() }
    }

    func loadCalendarList() {
        if let app = NSApplication.shared.delegate as! AppDelegate? {
            self.calendarsBySource = app.statusBarItem.eventStore.getAllCalendars()
        }
    }
}

struct AddAccountModal: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading) {
                Text(
                    """
                    To add external Calendars follow these steps:
                    1. Open the default Calendar App
                    2. Click 'Add Account' in the menu
                    3. Choose and connect your account
                    """
                )
            }
            Spacer()
            HStack {
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Close")
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

struct General: View {
    @Default(.showEventsForPeriod) var showEventsForPeriod
    @Default(.joinEventNotification) var joinEventNotification
    @Default(.joinEventNotificationTime) var joinEventNotificationTime

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Spacer()
            Section {
                Picker("Show events for", selection: $showEventsForPeriod) {
                    Text("today").tag(ShowEventsForPeriod.today)
                    Text("today and tomorrow").tag(ShowEventsForPeriod.today_n_tomorrow)
                }.frame(width: 270, alignment: .leading)
                HStack {
                    Toggle("Send notification to join next event meeting", isOn: $joinEventNotification)
                    Picker("", selection: $joinEventNotificationTime) {
                        Text("when event starts").tag(JoinEventNotificationTime.atStart)
                        Text("1 minute before").tag(JoinEventNotificationTime.minuteBefore)
                        Text("3 minute before").tag(JoinEventNotificationTime.threeMinuteBefore)
                        Text("5 minute before").tag(JoinEventNotificationTime.fiveMinuteBefore)
                    }.frame(width: 150, alignment: .leading).labelsHidden().disabled(!joinEventNotification)
                }
            }
            Section {
                HStack {
                    Text("Create meeting:")
                    KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
                    Spacer()
                    Text("Join next event meeting:")
                    KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                }
            }
            Spacer()
            Divider()
            AboutApp()
        }.padding()
    }
}

struct Appearance: View {
    @Default(.eventTitleFormat) var eventTitleFormat
    @Default(.titleLength) var titleLength

    @Default(.timeFormat) var timeFormat
    @Default(.showEventDetails) var showEventDetails
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.disablePastEvents) var disablePastEvents

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Status bar").font(.headline).bold()
            Section {
                Section {
                    HStack {
                        Picker("Show", selection: $eventTitleFormat) {
                            Text("event title").tag(EventTitleFormat.show)
                            Text("dot (•)").tag(EventTitleFormat.dot)
                        }
                    }
                    HStack {
                        Text(generateTitleSample(eventTitleFormat, Int(titleLength)))
                        Spacer()
                    }.padding(.all, 10)
                        .border(Color.gray, width: 3)
                    HStack {
                        Text("5")
                        Slider(value: $titleLength, in: TitleLengthLimits.min...TitleLengthLimits.max, step: 1)
                        Text("55")
                    }.disabled(eventTitleFormat != EventTitleFormat.show)
                    Text("Tip: If the app disappears from the status bar, make the length shorter").foregroundColor(Color.gray)
                }.padding(.horizontal, 10)
            }
            Divider()
            Text("Menu").font(.headline).bold()
            Section {
                HStack {
                    Toggle("Allow to join past event meeting", isOn: $disablePastEvents)
                    Spacer()
                    Toggle("Show event details as submenu", isOn: $showEventDetails)
                }
                HStack {
                    Picker("Declined events:", selection: $declinedEventsAppereance) {
                        Text("show with strikethrough").tag(DeclinedEventsAppereance.strikethrough)
                        Text("hide").tag(DeclinedEventsAppereance.hide)
                    }
                }
                HStack {
                    Picker("Time format:", selection: $timeFormat) {
                        Text("12-hour (AM/PM)").tag(TimeFormat.am_pm)
                        Text("24-hour").tag(TimeFormat.military)
                    }
                }
            }.padding(.horizontal, 10)
            Spacer()
        }.padding()
    }
}

struct Configuration: View {
    @Default(.useChromeForMeetLinks) var useChromeForMeetLinks
    @Default(.useChromeForHangoutsLinks) var useChromeForHangoutsLinks
    @Default(.useAppForZoomLinks) var useAppForZoomLinks
    @Default(.useAppForTeamsLinks) var useAppForTeamsLinks

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Section {
                Picker(selection: $useChromeForMeetLinks, label: Text("Open Meet links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Chrome").tag(true)
                }
                Picker(selection: $useChromeForHangoutsLinks, label: Text("Open Hangouts links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Chrome").tag(true)
                }
                Picker(selection: $useAppForZoomLinks, label: Text("Open Zoom links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Zoom app").tag(true)
                }
                Picker(selection: $useAppForTeamsLinks, label: Text("Open Teams links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Teams app").tag(true)
                }
            }.padding(.horizontal, 10)
            Spacer()
            Section {
                Text("Supported links for services:\n\(MeetingServices.allCases.map { $0.rawValue }.joined(separator: ", "))")
                HStack {
                    Text("If the service you use isn't supported, email me")
                    Button("✉️", action: emailMe)
                }
            }.foregroundColor(.gray).font(.system(size: 12)).padding(.horizontal, 10)
            Divider()
            HStack {
                Text("Create meetings in").frame(width: 150, alignment: .leading)
                CreateMeetingServicePicker()
            }.padding(.horizontal, 10)
        }.padding()
    }
}

struct CreateMeetingServicePicker: View {
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        Picker(selection: $createMeetingService, label: Text("")) {
            Text(MeetingServices.meet.rawValue).tag(MeetingServices.meet)
            Text(MeetingServices.zoom.rawValue).tag(MeetingServices.zoom)
            Text(MeetingServices.teams.rawValue).tag(MeetingServices.teams)
            Text(MeetingServices.hangouts.rawValue).tag(MeetingServices.hangouts)
        }.labelsHidden()
    }
}

func emailMe() {
    NSLog("Click email me")
    _ = openLinkInDefaultBrowser(Links.emailMe)
}
