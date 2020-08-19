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

struct MultipleSelectionRow: View {
    var title: String
    var isSelected: Bool
    var color: Color
    var action: () -> Void

    var body: some View {
        HStack {
            Button(action: self.action) {
                Text(self.isSelected ? "✔️" : "➕")
            }
            .background(self.color)
            Text(self.title)
        }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ContentView: View {
    // Appearance
    @Default(.eventTitleFormat) var eventTitleFormat
    @Default(.titleLength) var titleLength
    @Default(.etaFormat) var etaFormat

    @Default(.timeFormat) var timeFormat
    @Default(.showEventDetails) var showEventDetails
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.disablePastEvents) var disablePastEvents

    // Integrations
    @Default(.createMeetingService) var createMeetingService
    @Default(.useChromeForMeetLinks) var useChromeForMeetLinks
    @Default(.useChromeForHangoutsLinks) var useChromeForHangoutsLinks
    @Default(.useAppForZoomLinks) var useAppForZoomLinks
    @Default(.useAppForTeamsLinks) var useAppForTeamsLinks

    @Default(.joinEventNotification) var joinEventNotification

    // Calendars
    @Default(.selectedCalendarIDs) var selectedCalendarIDs

    let calendarsBySource: [String: [EKCalendar]]

    var body: some View {
        VStack {
            TabView {
                VStack(alignment: .leading, spacing: 15) {
                    Picker("Show events for ", selection: $eventTitleFormat) {
                        Text("today").tag(EventTitleFormat.show)
                        Text("today&tomorrow").tag(EventTitleFormat.hide)
                    }
                    Section {
                        Toggle("Send notification when event starting", isOn: $joinEventNotification)
                    }.padding(.horizontal, 10)
                    Divider()
                    Text("Global shortcuts").font(.headline).bold()
                    Section {
                        HStack {
                            Text("Create meeting:")
                            KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
                        }
                        HStack {
                            Text("Join next event:")
                            KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                        }
                    }.padding(.horizontal, 10)
                    Spacer()
                }.padding().tabItem { Text("General") }
                VStack(alignment: .leading, spacing: 15) {
                    Text("Status Bar").font(.headline).bold()
                    Section {
                        Section {
                            HStack {
                                Picker("title", selection: $eventTitleFormat) {
                                    Text("Show event title").tag(EventTitleFormat.show)
                                    Text("Show \"Meeting\"").tag(EventTitleFormat.hide)
                                    Text("Show dot (•)").tag(EventTitleFormat.dot)
                                }.labelsHidden()
                                Text("with")
                                Picker("eta", selection: $etaFormat) {
                                    Text("full").tag(ETAFormat.full)
                                    Text("short").tag(ETAFormat.short)
                                    Text("abbreviated").tag(ETAFormat.abbreviated)
                                }.labelsHidden()
                                Text("eta")
                            }
                            HStack {
                                Text(generateTitleSample(eventTitleFormat, etaFormat, Int(titleLength)))
                                Spacer()
                            }.padding(.all, 10)
                                .border(Color.gray, width: 3)
                            HStack {
                                Text("5")
                                Slider(value: $titleLength, in: TitleLengthLimits.min...TitleLengthLimits.max, step: 1)
                                Text("∞")
                            }.disabled(eventTitleFormat != EventTitleFormat.show)
                        }.padding(.horizontal, 10)
                    }
                    Divider()
                    Text("Menu").font(.headline).bold()
                    Section {
                        HStack {
                            Toggle("Disable past events", isOn: $disablePastEvents)
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
                }.padding().tabItem { Text("Appearance") }
                VStack(alignment: .leading, spacing: 15) {
                    Text("Services").font(.headline).bold()
                    Section {
                        Picker(selection: $createMeetingService, label: Text("Create meetings in ")) {
                            ForEach(MeetingServices.allCases.filter({ return $0 != .webex}), id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                    }.padding(.horizontal, 10)
                    Divider()
                    Section {
                        Picker("Open Meet links in", selection: $useChromeForMeetLinks) {
                            Text("Default Browser").tag(false)
                            Text("Chrome").tag(true)
                        }
                        Picker("Open Hangouts links in", selection: $useChromeForHangoutsLinks) {
                            Text("Default Browser").tag(false)
                            Text("Chrome").tag(true)
                        }
                        Picker("Open Zoom links in", selection: $useAppForZoomLinks) {
                            Text("Default Browser").tag(false)
                            Text("Zoom app").tag(true)
                        }
                        Picker("Open Teams links in", selection: $useAppForTeamsLinks) {
                            Text("Default Browser").tag(false)
                            Text("Teams app").tag(true)
                        }
                        Spacer()
                    }.pickerStyle(SegmentedPickerStyle()).padding(.horizontal, 10)
                }.padding().tabItem { Text("Integrations") }
                VStack(alignment: .leading, spacing: 15) {
                    Section {
                        Form {
                            Section(header: Text("Select your calendars:")) {
                                List {
                                    ForEach(Array(calendarsBySource.keys), id: \.self) { source in
                                        Section(header: Text(source)) {
                                            ForEach(self.calendarsBySource[source]!, id: \.self) { calendar in
                                                MultipleSelectionRow(title: calendar.title, isSelected: self.selectedCalendarIDs.contains(calendar.calendarIdentifier), color: Color(calendar.color)) {
                                                    if self.selectedCalendarIDs.contains(calendar.calendarIdentifier) {
                                                        self.selectedCalendarIDs.removeAll(where: { $0 == calendar.calendarIdentifier })
                                                    } else {
                                                        self.selectedCalendarIDs.append(calendar.calendarIdentifier)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }.padding().tabItem { Text("Calendars") }

                VStack(alignment: .leading, spacing: 15) {
                    Section {
                        VStack(alignment: .center) {
                            Spacer()
                            Image("icon").padding()
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
                }.padding().tabItem { Text("About") }
            }
        }.padding()
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
