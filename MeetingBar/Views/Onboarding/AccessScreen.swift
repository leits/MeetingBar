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
    @State var accessDenied: Bool
    @State var accessToEvents: Bool

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            if accessDenied {
                Text("Oops! It looks like you denied access to calendars.")
                Spacer()
                Text("Go to")
                Button("System Preferences", action: self.openSystemCalendarPreferences)
                Text("and select a checkbox near MeetingBar.")
                Spacer()
                Text("Then you need to launch the app manually to continue setting up.")
            } else {
                Text("Requesting your access to calendars.")
                Text("")
                Text("Click \"OK\" in popup window from MacOS.")
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
