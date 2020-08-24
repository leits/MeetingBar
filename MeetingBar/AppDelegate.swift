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
import UserNotifications

import Defaults
import KeyboardShortcuts

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusBarItem: StatusBarItemControler!

    var selectedCalendarIDsObserver: DefaultsObservation?
    var showEventDetailsObserver: DefaultsObservation?
    var titleLengthObserver: DefaultsObservation?
    var timeFormatObserver: DefaultsObservation?
    var eventTitleFormatObserver: DefaultsObservation?
    var disablePastEventObserver: DefaultsObservation?
    var declinedEventsAppereanceObserver: DefaultsObservation?
    var showEventsForPeriodObserver: DefaultsObservation?

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
            requestNotificationAuthorization()
            registerNotificationCategories()
            UNUserNotificationCenter.current().delegate = self

            // Backward compatibility
            if let oldEventTitleOption = Defaults[.showEventTitleInStatusBar] {
                Defaults[.eventTitleFormat] = oldEventTitleOption ? EventTitleFormat.show : EventTitleFormat.hide
                Defaults[.showEventTitleInStatusBar] = nil
            }

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
            //

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
            self.eventTitleFormatObserver = Defaults.observe(.eventTitleFormat) { change in
                NSLog("Changed eventTitleFormat from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
                self.statusBarItem.updateTitle()
            }
            self.titleLengthObserver = Defaults.observe(.titleLength) { change in
                NSLog("Changed titleLength from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
            }
            self.disablePastEventObserver = Defaults.observe(.disablePastEvents) { change in
                NSLog("Changed disablePastEvents from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
            self.declinedEventsAppereanceObserver = Defaults.observe(.declinedEventsAppereance) { change in
                NSLog("Changed declinedEventsAppereance from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
            self.showEventsForPeriodObserver = Defaults.observe(.showEventsForPeriod) { change in
                NSLog("Changed showEventsForPeriod from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }

        }
    }

    @objc func eventStoreChanged(notification _: NSNotification) {
        NSLog("Store changed. Update status bar menu.")
        statusBarItem.updateTitle()
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

    internal func userNotificationCenter(_: UNUserNotificationCenter,
                                         didReceive response: UNNotificationResponse,
                                         withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "JOIN_ACTION":
            NSLog("JOIN ACTION!")
            joinNextMeeting()
        default:
            break
        }

        completionHandler()
    }

    @objc func createMeeting(_: Any? = nil) {
        NSLog("Create meeting in \(Defaults[.createMeetingService].rawValue)")
        switch Defaults[.createMeetingService] {
        case .meet:
            openMeetingURL(MeetingServices.meet, Links.newMeetMeeting)
        case .zoom:
            openMeetingURL(MeetingServices.zoom, Links.newZoomMeeting)
        case .hangouts:
            openMeetingURL(MeetingServices.hangouts, Links.newHangoutsMeeting)
        case .teams:
            openMeetingURL(MeetingServices.teams, Links.newTeamsMeeting)
        default:
            break
        }
    }

    @objc func joinNextMeeting(_: NSStatusBarButton? = nil) {
        if let nextEvent = statusBarItem.eventStore.getNextEvent(calendars: statusBarItem.calendars) {
            NSLog("Join next event")
            openEvent(nextEvent)
        } else {
            NSLog("No next event")
            sendNotification("No next event", "There are no more meetings today")
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
        let calendarsBySource = Dictionary(grouping: calendars, by: { $0.source.title })

        let contentView = ContentView(calendarsBySource: calendarsBySource)
        if preferencesWindow != nil {
            preferencesWindow.close()
        }
        preferencesWindow = NSWindow(
            contentRect: NSMakeRect(0, 0, 570, 450),
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
