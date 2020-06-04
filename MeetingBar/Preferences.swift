//
//  ContentView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import Defaults
import EventKit
import SwiftUI
import KeyboardShortcuts


extension KeyboardShortcuts.Name {
    static let createMeetingShortcut = Name("createMeetingShortcut")
    static let joinEventShortcut = Name("joinEventShortcut")
}

struct ContentView: View {
    @Default(.calendarTitle) var calendarTitle
    @Default(.useChromeForMeetLinks) var useChromeForMeetLinks
//    @Default(.launchAtLogin) var launchAtLogin
    @Default(.showEventDetails) var showEventDetails
    @Default(.createMeetingService) var createMeetingService

    let calendars: [EKCalendar]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {

            Form {

                    Picker(selection: $calendarTitle, label: Text("Calendar:")) {
                        ForEach(0 ..< calendars.count) { index in
                            Text(self.calendars[index].title)
                                .foregroundColor(Color(self.calendars[index].color))
                                .tag(self.calendars[index].title)
                        }
                    }
                    Picker(selection: $createMeetingService, label: Text("Create meetings in ")) {
                        ForEach(MeetingServices.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
            }
            Divider()

            Toggle("Use Chrome for Google Meet links", isOn: $useChromeForMeetLinks)
            Toggle("Show event details", isOn: $showEventDetails)

                
            Divider()
            Form {

                HStack {
                    Text("Create meeting:")
                    KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
                }
                HStack {
                    Text("Join next event:")
                    KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                }
            }

//                Toggle(isOn: $launchAtLogin) {
//                    Text("Launch at login")
//                }
            Divider()
            HStack(alignment: .center) {
                Button("About this app", action: about)
                Spacer()
                Button("Support the creator", action: support)
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
