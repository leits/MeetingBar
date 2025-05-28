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
                Text("access_screen_provider_picker_label".loco()).font(.title).bold().padding(.bottom, 30)
                HStack(alignment: .top) {
                    VStack(spacing: 10) {
                        List {
                            Section(header:
                                Text("access_screen_provider_macos_title".loco()).font(.headline)
                            ) {
                                Text("access_screen_provider_macos_data_source".loco())
                                Text("access_screen_provider_macos_number_of_accounts".loco())
                                Text("access_screen_provider_macos_recommended".loco()).foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        VStack {
                            Button(action: { Task { await requestAccess(provider: .macOSEventKit) }}) {
                                Text("Use macOS Calendar").font(.headline)
                            }
                        }.frame(width: 200, height: 50)
                    }
                    VStack(spacing: 10) {
                        List {
                            Section(header: Text("Google Calendar API").font(.headline)) {
                                Text("access_screen_provider_gcalendar_data_source".loco())
                                Text("access_screen_provider_gcalendar_number_of_accounts".loco())
                            }
                        }
                        Spacer()
                        VStack {
                            Button(action: { Task { await requestAccess(provider: .googleCalendar) }}, label: {
                                Image("googleSignInButton").resizable().aspectRatio(contentMode: .fit).frame(width: 150)
                            }).buttonStyle(PlainButtonStyle())
                        }.frame(width: 200, height: 50)
                    }
                }
            } else {
                Spacer()
                if eventStoreProvider == .googleCalendar {
                    VStack(spacing: 20) {
                        Text("access_screen_provider_gcalendar_sign_in_title".loco()).bold()
                        Text("access_screen_provider_gcalendar_sign_in_description".loco())
                        Button("access_screen_try_again".loco()) { Task { await requestAccess(provider: .googleCalendar) } }
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

    @MainActor
    func requestAccess(provider: EventStoreProvider) async {
        providerSelected = true

        Defaults[.eventStoreProvider] = provider
        if let app = NSApplication.shared.delegate as! AppDelegate? {
            app.eventManager = await EventManager()
            await app.eventManager.changeEventStoreProvider(Defaults[.eventStoreProvider])
            Defaults[.onboardingCompleted] = true
            app.setup()
            self.viewRouter.currentScreen = .calendars
        }
    }
}
