//
//  AccessScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import EventKit
import SwiftUI

import Defaults

struct AccessScreen: View {
    @ObservedObject var viewRouter: ViewRouter

    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            if !GCEventStore.shared.isAuthed {
                Text("Google Sign In")
//                Spacer()
//                Text("access_screen_access_screen_access_denied_go_to_title".loco())
//                Button("access_screen_access_denied_system_preferences_button".loco(), action: self.openSystemCalendarPreferences)
//                Text("access_screen_access_denied_checkbox_title".loco())
//                Spacer()
//                Text("access_screen_access_denied_relaunch_title".loco())
            } else {
                Text("access_screen_access_granted_title".loco())
                Text("")
                Text("access_screen_access_granted_click_ok_title".loco())
            }
            Spacer()
        }.padding()
            .onAppear {
                self.requestAccess()
            }
    }

    func requestAccess() {
        EKEventStore().requestAccess(to: .event) { access, _ in
            NSLog("EventStore access: \(access)")
            _ = GCEventStore.shared.signIn().done {
                if GCEventStore.shared.isAuthed {
                    DispatchQueue.main.async {
                        Defaults[.onboardingCompleted] = true
                        if let app = NSApplication.shared.delegate as! AppDelegate? {
                            app.setup()
                        }
                        self.viewRouter.currentScreen = .calendars
                    }
                } else {
                    self.requestAccess()
                }
            }
        }
    }

//    func openSystemCalendarPreferences() {
//        NSWorkspace.shared.open(Links.calendarPreferences)
//    }
}
