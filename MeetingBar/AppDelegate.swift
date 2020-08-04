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
import KeyboardShortcuts

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: StatusBarItemControler!

    var selectedCalendarIDsObserver: DefaultsObservation?
    var showEventDetailsObserver: DefaultsObservation?
    var showEventTitleInStatusBarObserver: DefaultsObservation?
    var titleLengthObserver: DefaultsObservation?
    var timeFormatObserver: DefaultsObservation?

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
            
             // Backward compatibility
            var calendarTitles: [String] = []
            if Defaults[.calendarTitle] != "" {
                calendarTitles.append(Defaults[.calendarTitle])
                Defaults[.calendarTitle] = ""
            }
            if !Defaults[.selectedCalendars].isEmpty {
                calendarTitles.append(contentsOf: Defaults[.selectedCalendars])
                Defaults[.selectedCalendars] = []
            }
            if !calendarTitles.isEmpty {
                let matchCalendars = self.statusBarItem.eventStore.getCalendars(titles: calendarTitles)
                for calendar in matchCalendars {
                    Defaults[.selectedCalendarIDs].append(calendar.calendarIdentifier)
                }
                
            }
            self.statusBarItem.loadCalendars()

            self.scheduleUpdateStatusBarTitle()
            self.scheduleUpdateEvents()

            KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut) {
                self.createMeeting()
            }
            KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
                self.joinNextMeeting()
            }

            NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.eventStoreChanged), name: .EKEventStoreChanged, object: self.statusBarItem.eventStore)

            self.selectedCalendarIDsObserver = Defaults.observe(.selectedCalendarIDs) { change in
                NSLog("Changed selectedCalendarIDs from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.loadCalendars()
            }
            self.showEventDetailsObserver = Defaults.observe(.showEventDetails) { change in
                NSLog("Change showEventDetails from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
            self.timeFormatObserver = Defaults.observe(.timeFormat) { change in
                NSLog("Change timeFormat from \(change.oldValue) to \(change.newValue)")
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
        activity.qualityOfService = QualityOfService.userInteractive

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
        activity.qualityOfService = QualityOfService.userInteractive

        activity.schedule { (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            NSLog("Firing reccuring updateStatusBarMenu")
            self.statusBarItem.updateMenu()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    @objc func createMeeting(_: Any? = nil) {
        NSLog("Create meeting in \(Defaults[.createMeetingService].rawValue)")
        switch Defaults[.createMeetingService] {
        case .meet:
            if Defaults[.useChromeForMeetLinks] {
                openLinkInChrome(Links.newMeetMeeting)
            } else {
                openLinkInDefaultBrowser(Links.newMeetMeeting)
            }
        case .zoom:
            openLinkInDefaultBrowser(Links.newZoomMeeting)
        }
    }

    @objc func joinNextMeeting(_: NSStatusBarButton? = nil) {
        if let nextEvent = statusBarItem.eventStore.getNextEvent(calendars: statusBarItem.calendars) {
            NSLog("Join next event")
            openEvent(nextEvent)
        } else {
            NSLog("No next event")
            return
        }
    }
    
    
    @objc func clickOnEvent(sender: NSMenuItem) {
        NSLog("Click on event (\(sender.title))!")
        let event: EKEvent = sender.representedObject as! EKEvent
        openEvent(event)
    }

    @objc func openPrefecencesWindow(_: NSStatusBarButton?) {
        NSLog("Open preferences window")
        let calendars = statusBarItem.eventStore.calendars(for: .event)
        let contentView = ContentView(calendars: calendars)
        if preferencesWindow != nil {
            preferencesWindow.close()
        }
        preferencesWindow = NSWindow(
            contentRect: NSMakeRect(0, 0, 550, 430),
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
