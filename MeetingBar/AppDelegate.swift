//
//  AppDelegate.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import EventKit
import SwiftUI

import Defaults

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: StatusBarItemControler!

    var selectedCalendarsObserver: DefaultsObservation?
    var showEventDetailsObserver: DefaultsObservation?
    var showEventTitleInStatusBarObserver: DefaultsObservation?
    var titleLengthObserver: DefaultsObservation?

    var preferencesWindow: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        statusBarItem = StatusBarItemControler()

        statusBarItem.eventStore.accessCheck { result in
            switch result {
            case .success(let granted):
                if granted {
                    NSLog("Access to Calendar is granted")
                    self.setup()
                } else {
                    NSLog("Access to Calendar is denied")
                    NSApplication.shared.terminate(self)
                }
            case .failure(let error):
                NSLog(error.localizedDescription)
                NSApplication.shared.terminate(self)
            }
        }
    }

    func setup() {
        DispatchQueue.main.async {
            if Defaults[.calendarTitle] != "" {
                Defaults[.selectedCalendars].append(Defaults[.calendarTitle])
                Defaults[.calendarTitle] = ""
            }

            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()

            self.scheduleUpdateStatusBarTitle()
            self.scheduleUpdateEvents()

            NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.eventStoreChanged), name: .EKEventStoreChanged, object: self.statusBarItem.eventStore)

            self.selectedCalendarsObserver = Defaults.observe(.selectedCalendars) { change in
                NSLog("Changed selectedCalendars from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.calendars = self.statusBarItem.eventStore.getCalendars(change.newValue)
                self.statusBarItem.updateMenu()
                self.statusBarItem.updateTitle()
            }
            self.showEventDetailsObserver = Defaults.observe(.showEventDetails) { change in
                NSLog("Change showEventDetails from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
            self.showEventTitleInStatusBarObserver = Defaults.observe(.showEventTitleInStatusBar) { change in
                NSLog("Changed showEventTitleInStatusBar from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
            }
            self.titleLengthObserver = Defaults.observe(.titleLength) { change in
                NSLog("Changed titleLength from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
            }
        }
    }

    @objc func eventStoreChanged(notification _: NSNotification) {
        NSLog("Store changed. Update status bar menu.")
        statusBarItem.updateMenu()
    }

    private func scheduleUpdateStatusBarTitle() {
        let activity = NSBackgroundActivityScheduler(identifier: "leits.MeetingBar.updatestatusbartitle")

        activity.repeats = true
        activity.interval = 30
        activity.qualityOfService = QualityOfService.userInitiated

        activity.schedule { (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            NSLog("Firing reccuring updateStatusBarTitle")
            self.statusBarItem.updateTitle()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    private func scheduleUpdateEvents() {
        let activity = NSBackgroundActivityScheduler(identifier: "leits.MeetingBar.updateevents")

        activity.repeats = true
        activity.interval = 60 * 5
        activity.qualityOfService = QualityOfService.userInitiated

        activity.schedule { (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            NSLog("Firing reccuring updateStatusBarMenu")
            self.statusBarItem.updateMenu()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    @objc func openPrefecencesWindow(_: NSStatusBarButton?) {
        NSLog("Open preferences window")
        let calendars = statusBarItem.eventStore.calendars(for: .event)
        let contentView = ContentView(calendars: calendars)
        if preferencesWindow != nil {
            preferencesWindow.close()
        }
        preferencesWindow = NSWindow(
            contentRect: NSMakeRect(0, 0, 500, 430),
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false)
        preferencesWindow.title = "MeetingBar preferences"
        preferencesWindow.contentView = NSHostingView(rootView: contentView)
        let controller = NSWindowController(window: preferencesWindow)
        controller.showWindow(self)

        preferencesWindow.center()
        preferencesWindow.orderFrontRegardless()
    }

    @objc func quit(_: NSStatusBarButton) {
        NSLog("User click Quit")
        NSApplication.shared.terminate(self)
    }
}
