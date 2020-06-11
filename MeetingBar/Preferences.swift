//
//  ContentView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit
import SwiftUI

import Defaults
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let createMeetingShortcut = Name("createMeetingShortcut")
    static let joinEventShortcut = Name("joinEventShortcut")
}

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

func generateTitle(_ showTitle: Bool, _ offset: Int) -> String {
    var title: String = "Meeting"
    if showTitle {
        title = "Long title which may not be displayed in your status bar"
        let index = title.index(title.startIndex, offsetBy: offset, limitedBy: title.endIndex)
        title = String(title[...(index ?? title.endIndex)])
        if offset < Int(TitleLengthLimits.max) {
            title += "..."
        }
    }
    return "\(title) in 5 min"

}

struct ContentView: View {
    @Default(.useChromeForMeetLinks) var useChromeForMeetLinks
//    @Default(.launchAtLogin) var launchAtLogin
    @Default(.showEventDetails) var showEventDetails
    @Default(.createMeetingService) var createMeetingService
    @Default(.selectedCalendars) var selectedCalendars
    @Default(.showEventTitleInStatusBar) var showEventTitleInStatusBar
    @Default(.titleLength) var titleLength
    let calendars: [EKCalendar]

    var body: some View {
        VStack{
            TabView {
            VStack(alignment: .leading, spacing: 15) {
                Section {
                    Section {
                        Toggle("Show event title in status bar", isOn: $showEventTitleInStatusBar)
                        HStack {
                            Text(generateTitle(showEventTitleInStatusBar, Int(titleLength)))
                            Spacer()
                        }.padding(.all, 10)
                            .border(Color.gray, width: 3)
                        HStack {
                            Text("5")
                            Slider(value: $titleLength, in: TitleLengthLimits.min...TitleLengthLimits.max, step: 1)
                            Text("∞")
                        }.disabled(!showEventTitleInStatusBar)
                        Divider()
                    }
                    Section {
                        Toggle("Show event details as submenu", isOn: $showEventDetails)
                        Divider()
                        Picker(selection: $createMeetingService, label: Text("Create meetings in ")) {
                            ForEach(MeetingServices.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        Toggle("Use Chrome for Google Meet links", isOn: $useChromeForMeetLinks)
                        Divider()
                        HStack {
                            Text("Create meeting:")
                            KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
                        }
                        HStack {
                            Text("Join next event:")
                            KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                        }
                    }
                }
            }.padding().tabItem { Text("General") }
                
            VStack(alignment: .leading, spacing: 15) {
                Section {
                    Form {
                        Text("Select your calendars:")
                        List(calendars, id: \.calendarIdentifier) { calendar in
                            MultipleSelectionRow(title: calendar.title, isSelected: self.selectedCalendars.contains(calendar.title), color: Color(calendar.color)) {
                                if self.selectedCalendars.contains(calendar.title) {
                                    self.selectedCalendars.removeAll(where: { $0 == calendar.title })
                                } else {
                                    self.selectedCalendars.append(calendar.title)
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
                        if Bundle.main.infoDictionary != nil{
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")").foregroundColor(.gray)
                        }
                        Spacer()
                        Spacer()
                        HStack{
                            Button("About this app", action: about)
                            Spacer()
                            Button("Support the creator", action: support)
                            
                        }
                    }
                }
            }.padding().tabItem { Text("About") }
        }
        }.padding()
    }
}

func about() {
    NSLog("User click About")
    let projectLink = URL(string: "https://github.com/leits/MeetingBar")!
    openLinkInDefaultBrowser(projectLink)
}

func support() {
    NSLog("User click Support")
    let projectLink = URL(string: "https://www.patreon.com/meetingbar")!
    openLinkInDefaultBrowser(projectLink)
}
