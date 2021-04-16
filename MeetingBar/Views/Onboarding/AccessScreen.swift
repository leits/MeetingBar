//
//  AccessScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI
import EventKit

import Defaults

struct AccessScreen: View {
    @ObservedObject var viewRouter: ViewRouter
    @State var accessDenied = false
    @State var accessToEvents = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            if accessDenied {
                Text("access_screen_access_denied_title".loco())
                Spacer()
                Text("access_screen_access_screen_access_denied_go_to_title".loco())
                Button("access_screen_access_denied_system_preferences_button".loco(), action: self.openSystemCalendarPreferences)
                Text("access_screen_access_denied_checkbox_title".loco())
                Spacer()
                Text("access_screen_access_denied_relaunch_title".loco())
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
            .onReceive(timer) { _ in
                if self.accessDenied {
                    self.checkAccess()
                }
            }
    }

    func requestAccess() {
        EKEventStore().requestAccess(to: .event) { access, _ in
            NSLog("EventStore access: \(access)")
            self.checkAccess()
            self.accessDenied = !access
        }
    }

    func checkAccess() {
        if EKEventStore.authorizationStatus(for: .event) == .authorized {
            DispatchQueue.main.async {
                Defaults[.onboardingCompleted] = true
                if let app = NSApplication.shared.delegate as! AppDelegate? {
                    app.setup()
                }
                self.viewRouter.currentScreen = .calendars
            }
        }
    }

    func openSystemCalendarPreferences() {
        NSWorkspace.shared.open(Links.calendarPreferences)
    }
}
