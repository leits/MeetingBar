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
import ServiceManagement

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusBarItem: StatusBarItemControler!

    var selectedCalendarIDsObserver: DefaultsObservation?
    var showEventDetailsObserver: DefaultsObservation?
    var titleLengthObserver: DefaultsObservation?
    var timeFormatObserver: DefaultsObservation?
    var eventTitleFormatObserver: DefaultsObservation?
    var disablePastEventObserver: DefaultsObservation?
    var hidePastEventObserver: DefaultsObservation?
    var declinedEventsAppereanceObserver: DefaultsObservation?
    var showEventsForPeriodObserver: DefaultsObservation?
    var joinEventNotificationObserver: DefaultsObservation?
    var launchAtLoginObserver: DefaultsObservation?

    var preferencesWindow: NSWindow!
    var onboardingWindow: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        // Backward compatibility
        if let oldEventTitleOption = Defaults[.showEventTitleInStatusBar] {
            Defaults[.eventTitleFormat] = oldEventTitleOption ? EventTitleFormat.show : EventTitleFormat.dot
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
            let matchCalendars = statusBarItem.eventStore.getMatchedCalendars(titles: calendarTitles)
            for calendar in matchCalendars {
                Defaults[.selectedCalendarIDs].append(calendar.calendarIdentifier)
            }
        }
        //

        let eventStoreAuthorized = (EKEventStore.authorizationStatus(for: .event) == .authorized)
        if Defaults[.onboardingCompleted], eventStoreAuthorized {
            setup()
        } else {
            openOnboardingWindow()
        }
        
        // When our main application starts, we have to kill
        // the auto launcher application if it's still running.
        postNotificationForAutoLauncher()
    }
    
    /// Sending a notification to AutoLauncher app
    /// about main application running status
    private func postNotificationForAutoLauncher() {
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = !runningApps.filter { $0.bundleIdentifier == AutoLauncher.bundleIdentifier }.isEmpty
        if isRunning {
            DistributedNotificationCenter.default().post(name: .killAutoLauncher,
                                                         object: Bundle.main.bundleIdentifier)
        }
    }

    func setup() {
        statusBarItem = StatusBarItemControler()

        registerNotificationCategories()
        UNUserNotificationCenter.current().delegate = self

        statusBarItem.loadCalendars()

        scheduleUpdateStatusBarTitle()
        scheduleUpdateEvents()

        KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut) {
            self.createMeeting()
        }
        KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
            self.joinNextMeeting()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.eventStoreChanged), name: .EKEventStoreChanged, object: statusBarItem.eventStore)

        selectedCalendarIDsObserver = Defaults.observe(.selectedCalendarIDs) { change in
            NSLog("Changed selectedCalendarIDs from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.loadCalendars()
        }
        showEventDetailsObserver = Defaults.observe(.showEventDetails) { change in
            NSLog("Change showEventDetails from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }
        timeFormatObserver = Defaults.observe(.timeFormat) { change in
            NSLog("Change timeFormat from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }
        eventTitleFormatObserver = Defaults.observe(.eventTitleFormat) { change in
            NSLog("Changed eventTitleFormat from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
            self.statusBarItem.updateTitle()
        }
        titleLengthObserver = Defaults.observe(.titleLength) { change in
            NSLog("Changed titleLength from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateTitle()
        }
        disablePastEventObserver = Defaults.observe(.disablePastEvents) { change in
            NSLog("Changed disablePastEvents from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }
        hidePastEventObserver = Defaults.observe(.hidePastEvents) { change in
            NSLog("Changed hidePastEvents from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }
        declinedEventsAppereanceObserver = Defaults.observe(.declinedEventsAppereance) { change in
            NSLog("Changed declinedEventsAppereance from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }
        showEventsForPeriodObserver = Defaults.observe(.showEventsForPeriod) { change in
            NSLog("Changed showEventsForPeriod from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
        }
        launchAtLoginObserver = Defaults.observe(.launchAtLogin) { change in
            NSLog("Changed launchAtLogin from \(change.oldValue) to \(change.newValue)")
            SMLoginItemSetEnabled(AutoLauncher.bundleIdentifier as CFString, change.newValue)
        }
        joinEventNotificationObserver = Defaults.observe(.joinEventNotification) { change in
            NSLog("Changed joinEventNotification from \(change.oldValue) to \(change.newValue)")
            if change.newValue == true {
                if let nextEvent = self.statusBarItem.eventStore.getNextEvent(calendars: self.statusBarItem.calendars) {
                    scheduleEventNotification(nextEvent)
                }
            } else {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
        }
    }

    @objc
    func eventStoreChanged(notification _: NSNotification) {
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

    internal func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "JOIN_ACTION", UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == "EVENT" {
                if let eventID = response.notification.request.content.userInfo["eventID"] {
                    // built-in method EKEventStore.event(withIdentifier:) is broken
                    // temporary allow to open only the last event
                    if let nextEvent = statusBarItem.eventStore.getNextEvent(calendars: statusBarItem.calendars) {
                        if nextEvent.eventIdentifier == (eventID as! String) {
                            NSLog("Join \(nextEvent.title ?? "No title") event from notication")
                            openEvent(nextEvent)
                        }
                    }
                }
            }
        default:
            break
        }

        completionHandler()
    }

    @objc
    func createMeeting(_: Any? = nil) {
        NSLog("Create meeting in \(Defaults[.createMeetingService].rawValue)")
        switch Defaults[.createMeetingService] {
        case .meet:
            openMeetingURL(MeetingServices.meet, CreateMeetingLinks.meet)
        case .zoom:
            openMeetingURL(MeetingServices.zoom, CreateMeetingLinks.zoom)
        case .hangouts:
            openMeetingURL(MeetingServices.hangouts, CreateMeetingLinks.hangouts)
        case .teams:
            openMeetingURL(MeetingServices.teams, CreateMeetingLinks.teams)
        default:
            break
        }
    }

    @objc
    func joinNextMeeting(_: NSStatusBarButton? = nil) {
        if let nextEvent = statusBarItem.eventStore.getNextEvent(calendars: statusBarItem.calendars) {
            NSLog("Join next event")
            openEvent(nextEvent)
        } else {
            NSLog("No next event")
            sendNotification("There are no next meetings today", "Woohoo! It's time to make cocoa")
            return
        }
    }

    @objc
    func clickOnEvent(sender: NSMenuItem) {
        NSLog("Click on event (\(sender.title))!")
        let event: EKEvent = sender.representedObject as! EKEvent
        openEvent(event)
    }

    @objc
    func openPrefecencesWindow(_: NSStatusBarButton?) {
        NSLog("Open preferences window")
        let contentView = PreferencesView()
        if preferencesWindow != nil {
            preferencesWindow.close()
        }
        preferencesWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 450),
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false)
        preferencesWindow.title = "MeetingBar Preferences"
        preferencesWindow.contentView = NSHostingView(rootView: contentView)
        let controller = NSWindowController(window: preferencesWindow)
        controller.showWindow(self)

        preferencesWindow.center()
        preferencesWindow.orderFrontRegardless()
    }

    func openOnboardingWindow() {
        NSLog("Open onboarding window")

        let contentView = OnboardingView()
        if onboardingWindow != nil {
            onboardingWindow.close()
        }
        onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false)
        onboardingWindow.title = "Welcome to MeetingBar!"
        onboardingWindow.contentView = NSHostingView(rootView: contentView)
        let controller = NSWindowController(window: onboardingWindow)
        controller.showWindow(self)

        onboardingWindow.level = NSWindow.Level.floating
        onboardingWindow.center()
        onboardingWindow.orderFrontRegardless()
    }

    @objc
    func quit(_: NSStatusBarButton) {
        NSLog("User click Quit")
        NSApplication.shared.terminate(self)
    }
}
