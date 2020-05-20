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

struct ContentView: View {
    @Default(.calendarTitle) var calendarTitle
    @Default(.useChromeForMeetLinks) var useChromeForMeetLinks
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.showEventDetails) var showEventDetails
    @Default(.createMeetingService) var createMeetingService

    let calendars: [EKCalendar]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
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
            Toggle(isOn: $useChromeForMeetLinks) {
                Text("Use Chrome for Google Meet links")
            }
            Toggle(isOn: $showEventDetails) {
                Text("Show event details")
            }
            Divider()
            Toggle(isOn: $launchAtLogin) {
                Text("Launch at login")
            }
            Divider()
            HStack{
                Button("About this app", action: about)
                Button("Quit MeetingBar", action: quit).offset(x: 240)
            }

        }.padding()
    }
}

func quit() {
    NSLog("User click Quit")
    NSApplication.shared.terminate(nil)
}

func about() {
    NSLog("User click About")
    let projectLink = "https://github.com/leits/MeetingBar"
    openLinkInDefaultBrowser(projectLink)
}
