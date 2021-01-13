//
//  WelcomeScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults
import KeyboardShortcuts

struct WelcomeScreen: View {
    @ObservedObject var viewRouter: ViewRouter
    @Default(.launchAtLogin) var launchAtLogin

    var body: some View {
        VStack {
            VStack {
                VStack {
                    Spacer()
                    Text("Hi! MeetingBar is such a simple app that everything is almost ready.")
                    Text("Let’s make it 100% yours!")
                    Spacer()
                }
                Divider()
                HStack {
                    Toggle("Launch MeetingBar at Login", isOn: $launchAtLogin)
                    Spacer()
                }.padding(10)
                Divider()
                HStack {
                    Text("Join next event meeting with your shortcut:")
                    KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                    Spacer()
                }.padding(5)
                HStack {
                    Text("Create ad hoc meetings in ")
                    HStack {
                        CreateMeetingServicePicker()
                    }.frame(width: 145)
                    Spacer()
                }.padding(5)
                HStack {
                    Text("with your shortcut:")
                    KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
                    Spacer()
                }.padding(5)
                Spacer()
                JoinEventNotificationPicker()
                Spacer()
            }
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(action: { self.viewRouter.currentScreen = .access }) {
                    Text("Setup calendars")
                    Image(nsImage: NSImage(named: NSImage.goForwardTemplateName)!)
                }
            }.padding(5)
        }
    }
}
