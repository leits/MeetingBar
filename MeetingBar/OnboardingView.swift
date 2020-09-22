//
//  OnboardingView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import Combine

import EventKit
import SwiftUI
import UserNotifications

import Defaults
import KeyboardShortcuts

enum Screens {
    case welcome
    case access
    case calendars
}

class ViewRouter: ObservableObject {
    let objectWillChange = PassthroughSubject<ViewRouter, Never>()

    var currentScreen: Screens = .welcome {
        didSet {
            objectWillChange.send(self)
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var viewRouter: ViewRouter = ViewRouter()

    var body: some View {
        VStack(alignment: .leading) {
            if viewRouter.currentScreen == .welcome {
                WelcomeScreenView(viewRouter: viewRouter).padding()
            }
            if viewRouter.currentScreen == .access {
                AccessScreenView(viewRouter: viewRouter).padding()
            }
            if viewRouter.currentScreen == .calendars {
                CalendarsScreenView().padding()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

struct WelcomeScreenView: View {
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

struct AccessScreenView: View {
    @ObservedObject var viewRouter: ViewRouter
    @State var accessDenied: Bool = false
    @State var accessToEvents: Bool = false

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

struct CalendarsScreenView: View {
    @Default(.selectedCalendarIDs) var selectedCalendarIDs

    var body: some View {
        VStack {
            Calendars()
            Divider()
            HStack {
                Spacer()
                if self.selectedCalendarIDs.count == 0 {
                    Text("Select at least one calendar").foregroundColor(Color.gray)
                }
                Button(action: self.close) {
                    Text("Start using app")
                    Image(nsImage: NSImage(named: NSImage.goForwardTemplateName)!)
                }.disabled(self.selectedCalendarIDs.count == 0)
            }.padding(5)
        }
    }

    func close() {
        if let app = NSApplication.shared.delegate as! AppDelegate? {
            app.onboardingWindow.close()
        }
    }
}
