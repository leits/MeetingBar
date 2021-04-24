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
                    Text("welcome_screen_greeting_main_title".loco())
                    Text("welcome_screen_greeting_additional_title".loco())
                    Spacer()
                }
                Divider()
                HStack {
                    Toggle("welcome_screen_login_launch_toggle_title".loco(), isOn: $launchAtLogin)
                    Spacer()
                }.padding(10)
                Divider()
                HStack {
                    Text("welcome_screen_shortcut_next_meeting_title".loco())
                    KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                    Spacer()
                }.padding(5)
                HStack {
                    Text("welcome_screen_ad_hoc_meeting_title".loco())
                    HStack {
                        CreateMeetingServicePicker()
                    }.frame(width: 145)
                    Spacer()
                }.padding(5)
                HStack {
                    Text("welcome_screen_shortcut_ad_hoc_meeting_title".loco())
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
                    Text("welcome_screen_setup_calendar_title".loco())
                    Image(nsImage: NSImage(named: NSImage.goForwardTemplateName)!)
                }
            }.padding(5)
        }
    }
}
