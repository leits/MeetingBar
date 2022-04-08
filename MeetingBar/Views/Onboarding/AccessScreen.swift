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
    @Default(.eventStoreProvider) var eventStoreProvider
    @State var providerSelected = false
    @State var requestFailed = false

    var body: some View {
        VStack(alignment: .center) {
            if !providerSelected {
                Text("Select calendars provider").font(.title).bold().padding(.bottom, 30)
                HStack(alignment: .top) {
                    VStack(spacing: 10) {
                        List {
                            Button("MacOS Calendar app") { requestAccess(provider: .MacOSEventKit) }
                            Text("(recomended)").foregroundColor(Color(NSColor.gray))
                            Text("Get data from MacOS Calendar app")
                            Text("Any number of any connected accounts")
                        }
                    }
                    VStack(spacing: 10) {
                        List {
                            Button("Google Calendar API") { requestAccess(provider: .GoogleCalendar) }.padding(.bottom, 24)
                            Text("Get data directly from Google Calendar")
                            Text("Only one Google account")
                        }
                    }
                }
            } else {
                Spacer()
                if eventStoreProvider == .GoogleCalendar {
                    VStack(spacing: 20) {
                        Text("Google Sign In").bold()
                        Text("Allow MeetingBar access to your calendar in browser window")
                        Button("Try again") { requestAccess(provider: .GoogleCalendar) }
                    }
                } else {
                    if !requestFailed {
                        Text("access_screen_access_granted_title".loco())
                        Text("")
                        Text("access_screen_access_granted_click_ok_title".loco())
                    } else {
                        VStack(alignment: .center, spacing: 10) {
                            HStack {
                                Text("access_screen_access_screen_access_denied_go_to_title".loco())
                                Button("access_screen_access_denied_system_preferences_button".loco()) { NSWorkspace.shared.open(Links.calendarPreferences) }
                                Text("access_screen_access_denied_checkbox_title".loco())
                            }
                            Text("access_screen_access_denied_relaunch_title".loco())
                        }
                    }
                }
                Spacer()
            }
        }.padding()
    }

    func requestAccess(provider: eventStoreProvider) {
        providerSelected = true

        Defaults[.eventStoreProvider] = provider
        if let app = NSApplication.shared.delegate as! AppDelegate? {
            app.setEventStoreProvider(provider: provider)
            _ = app.eventStore.signIn().done {
                DispatchQueue.main.async {
                    Defaults[.onboardingCompleted] = true
                    app.setup()
                    app.statusBarItem.loadCalendars()

                    self.viewRouter.currentScreen = .calendars
                }
            }.catch { _ in
                requestFailed = true
            }
        }
    }
}
