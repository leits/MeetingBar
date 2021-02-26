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
    var showMeetingServiceIconObserver: DefaultsObservation?

    var allDayEventsObserver: DefaultsObservation?

    var statusbarEventTitleLengthObserver: DefaultsObservation?
    var timeFormatObserver: DefaultsObservation?
    var bookmarksObserver: DefaultsObservation?

    var eventTitleFormatObserver: DefaultsObservation?
    var eventTimeFormatObserver: DefaultsObservation?

    var eventTitleIconFormatObserver: DefaultsObservation?

    var shortenEventTitleObserver: DefaultsObservation?
    var menuEventTitleLengthObserver: DefaultsObservation?
    var showEventEndTimeObserver: DefaultsObservation?
    var pastEventsAppereanceObserver: DefaultsObservation?
    var disablePastEventObserver: DefaultsObservation?
    var showPendingEventObserver: DefaultsObservation?
    var declinedEventsAppereanceObserver: DefaultsObservation?
    var personalEventsAppereanceObserver: DefaultsObservation?
    var showEventsForPeriodObserver: DefaultsObservation?
    var ignoredEventIDsObserver: DefaultsObservation?
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
        if let disablePastEvents = Defaults[.disablePastEvents] {
            Defaults[.pastEventsAppereance] = disablePastEvents ? .show_inactive : .show_active
            Defaults[.disablePastEvents] = nil
        }

        if let titleLength = Defaults[.titleLength] {
            Defaults[.statusbarEventTitleLength] = Int(titleLength)
            Defaults[.titleLength] = nil
        }
        if let useChromeForMeetLinks = Defaults[.useChromeForMeetLinks] {
            if useChromeForMeetLinks {
                let chromeBrowser = Defaults[.browser].first(where: { $0.name == "Google Chrome" })
                Defaults[.browserForMeetLinks] = chromeBrowser!
            } else {
                Defaults[.browserForMeetLinks] = Browser(name: "Default Browser", path: "", arguments: "", deletable: false)
            }


            Defaults[.useChromeForMeetLinks] = nil
        }

        // AppStore sync
        completeStoreTransactions()
        checkAppSource()

        //

        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            Defaults[.appVersion] = appVersion
        }

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
        let isRunning = runningApps.contains { $0.bundleIdentifier == AutoLauncher.bundleIdentifier }
        if isRunning {
            let killAutoLauncherNotificationName = Notification.Name(rawValue: "killAutoLauncher")
            DistributedNotificationCenter.default().post(name: killAutoLauncherNotificationName,
                                                         object: Bundle.main.bundleIdentifier)
        }
    }

    func setup() {
        statusBarItem = StatusBarItemControler()
        statusBarItem.setAppDelegate(appdelegate: self)

        registerNotificationCategories()
        UNUserNotificationCenter.current().delegate = self

        statusBarItem.loadCalendars()

        scheduleUpdateStatusBarTitle()
        scheduleUpdateEvents()

        if Defaults[.browser].isEmpty {
            addInstalledBrowser()
        }


        KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut) {
            self.createMeeting()
        }
        KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
            self.joinNextMeeting()
        }

        KeyboardShortcuts.onKeyUp(for: .openMenuShortcut) {
            // show the menu as normal
            self.statusBarItem.statusItem.menu = self.statusBarItem.statusItemMenu
            self.statusBarItem.statusItem.button?.performClick(nil) // ...and click
        }

        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.eventStoreChanged), name: .EKEventStoreChanged, object: statusBarItem.eventStore)


        showEventDetailsObserver = Defaults.observe(.showEventDetails) { change in
            NSLog("Change showEventDetails from \(change.oldValue) to \(change.newValue)")
            if change.oldValue != change.newValue {
                self.statusBarItem.updateMenu()
            }
        }


        shortenEventTitleObserver = Defaults.observe(.shortenEventTitle) { change in
            NSLog("Change shortenEventTitle from \(change.oldValue) to \(change.newValue)")
            if change.oldValue != change.newValue {
                self.statusBarItem.updateMenu()
            }
        }

        menuEventTitleLengthObserver = Defaults.observe(.menuEventTitleLength) { change in
            NSLog("Change menuEventTitleLengthObserver from \(change.oldValue) to \(change.newValue)")
            if change.oldValue != change.newValue {
                self.statusBarItem.updateMenu()
            }
        }

        showEventEndTimeObserver = Defaults.observe(.showEventEndTime) { change in
            NSLog("Change showEventEndTime from \(change.oldValue) to \(change.newValue)")
            if change.oldValue != change.newValue {
                self.statusBarItem.updateMenu()
            }
        }

        eventTimeFormatObserver = Defaults.observe(.eventTimeFormat) { change in
            NSLog("Changed eventTimeFormat from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
            if change.oldValue != change.newValue {
                self.statusBarItem.updateTitle()
            }
        }

        statusbarEventTitleLengthObserver = Defaults.observe(.statusbarEventTitleLength) { change in
            NSLog("Changed statusbarEventTitleLengthLimits from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateTitle()
        }

        disablePastEventObserver = Defaults.observe(.disablePastEvents) { change in
            NSLog("Changed disablePastEvents from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
            self.statusBarItem.updateMenu()
        }

        showPendingEventObserver = Defaults.observe(.showPendingEvents) { change in
            NSLog("Changed showPendingEvents from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")

            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
        }

        selectedCalendarIDsObserver = Defaults.observe(.selectedCalendarIDs) { change in
            NSLog("Changed selectedCalendarIDs from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.loadCalendars()
        }

        showMeetingServiceIconObserver = Defaults.observe(.showMeetingServiceIcon) { change in
            NSLog("Change showMeetingServiceIcon from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }

        allDayEventsObserver = Defaults.observe(.allDayEvents) { change in
            NSLog("Change allDayEvents from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
        }

        timeFormatObserver = Defaults.observe(.timeFormat) { change in
            NSLog("Change timeFormat from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }

        bookmarksObserver = Defaults.observe(keys: .bookmarks) {
                self.statusBarItem.updateMenu()
        }

        eventTitleFormatObserver = Defaults.observe(.eventTitleFormat) { change in
            NSLog("Changed eventTitleFormat from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
            self.statusBarItem.updateTitle()
        }

        eventTitleIconFormatObserver = Defaults.observe(.eventTitleIconFormat) { change in
            NSLog("Changed eventTitleFormat from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
            self.statusBarItem.updateTitle()
        }


        pastEventsAppereanceObserver = Defaults.observe(.pastEventsAppereance) { change in
            NSLog("Changed pastEventsAppereance from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }
        declinedEventsAppereanceObserver = Defaults.observe(.declinedEventsAppereance) { change in
            NSLog("Changed declinedEventsAppereance from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateMenu()
        }
        personalEventsAppereanceObserver = Defaults.observe(.personalEventsAppereance) { change in
            NSLog("Changed personalEventsAppereance from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateTitle()
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
            DispatchQueue.main.async {
                self.statusBarItem.updateMenu()
            }
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    /**
     * implementation is necessary to show notifications even when the app has focus!
     */
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])     }

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
        case .gcalendar:
            openMeetingURL(nil, CreateMeetingLinks.gcalendar)
        case .outlook_office365:
            openMeetingURL(nil, CreateMeetingLinks.outlook_office365)
        case .outlook_live:
            openMeetingURL(nil, CreateMeetingLinks.outlook_live)
        case .url:
            var url: String = Defaults[.createMeetingServiceUrl]
            let checkedUrl = NSURL(string: url)

            if !url.isEmpty && checkedUrl != nil {
                openMeetingURL(nil, URL(string: url)!)
            } else {
                if !url.isEmpty {
                    url += " "
                }

                sendNotification("Cannot create new meeeting", "Custom url \(url)is missing or invalid. Please enter a value in the app preferences.")
            }
        }
    }

    @objc
    func joinBookmark(sender: NSMenuItem) {
        NSLog("Join bookmark")
        if let bookmark: Bookmark = sender.representedObject as? Bookmark {
            guard let url = URL(string: bookmark.url) else {
                return
            }
            openMeetingURL(bookmark.service, url)
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
    func openEventInCalendar(sender: NSMenuItem) {
        if let identifier = sender.representedObject as? String {
            let url = URL(string: "ical://ekevent/\(identifier)")!
            url.openInDefaultBrowser()
        }
    }

    @objc
    func openPrefecencesWindow(_: NSStatusBarButton?) {
        NSLog("Open preferences window")
        let contentView = PreferencesView()
        if preferencesWindow != nil {
            preferencesWindow.close()
        }
        preferencesWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
            styleMask: [.closable, .titled, .resizable],
            backing: .buffered,
            defer: false
        )
        preferencesWindow.title = "MeetingBar Preferences"
        preferencesWindow.contentView = NSHostingView(rootView: contentView)
        preferencesWindow.makeKeyAndOrderFront(nil)
        // allow the preference window can be focused automatically when opened
        NSApplication.shared.activate(ignoringOtherApps: true)

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
            defer: false
        )
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
