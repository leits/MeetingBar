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

    var titleLengthObserver: DefaultsObservation?
    var timeFormatObserver: DefaultsObservation?
    var bookmarkObserver: DefaultsObservation?

    var eventTitleFormatObserver: DefaultsObservation?
    var eventTimeFormatObserver: DefaultsObservation?

    var eventTitleIconFormatObserver: DefaultsObservation?

    var shortenEventTitleObserver: DefaultsObservation?
    var menuEventTitleLengthObserver: DefaultsObservation?
    var showEventEndDateObserver: DefaultsObservation?
    var pastEventsAppereanceObserver: DefaultsObservation?
    var disablePastEventObserver: DefaultsObservation?
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

        KeyboardShortcuts.onKeyUp(for: .joinBookmarkShortcut1) {
            self.joinBookmark()
        }
        KeyboardShortcuts.onKeyUp(for: .joinBookmarkShortcut2) {
            self.joinBookmark2()
        }
        KeyboardShortcuts.onKeyUp(for: .joinBookmarkShortcut3) {
            self.joinBookmark3()
        }
        KeyboardShortcuts.onKeyUp(for: .joinBookmarkShortcut4) {
            self.joinBookmark4()
        }
        KeyboardShortcuts.onKeyUp(for: .joinBookmarkShortcut5) {
            self.joinBookmark5()
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

        showEventEndDateObserver = Defaults.observe(.showEventEndDate) { change in
            NSLog("Change showEventEndDate from \(change.oldValue) to \(change.newValue)")
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

        titleLengthObserver = Defaults.observe(.titleLength) { change in
            NSLog("Changed titleLength from \(change.oldValue) to \(change.newValue)")
            self.statusBarItem.updateTitle()
        }

        disablePastEventObserver = Defaults.observe(.disablePastEvents) { change in
            NSLog("Changed disablePastEvents from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
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

        bookmarkObserver = Defaults.observe(keys: .bookmarkMeetingURL, .bookmarkMeetingURL2, .bookmarkMeetingURL3, .bookmarkMeetingURL4, .bookmarkMeetingURL5, .bookmarkMeetingName, .bookmarkMeetingName2, .bookmarkMeetingName3, .bookmarkMeetingName4, .bookmarkMeetingName5, .bookmarkMeetingService, .bookmarkMeetingService2, .bookmarkMeetingService3, .bookmarkMeetingService4, .bookmarkMeetingService5) {
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
        }
    }

    func joinBookmarkInternal(urlString: String, service: MeetingServices) {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            return
        }
        openMeetingURL(service, url)
    }

    @objc
    func joinBookmark2(_: Any? = nil) {
        NSLog("Join bookmark 2")
        joinBookmarkInternal(urlString: Defaults[.bookmarkMeetingURL2], service: Defaults[.bookmarkMeetingService2])
    }

    @objc
    func joinBookmark3(_: Any? = nil) {
        NSLog("Join bookmark 3")
        joinBookmarkInternal(urlString: Defaults[.bookmarkMeetingURL3], service: Defaults[.bookmarkMeetingService3])
    }

    @objc
    func joinBookmark4(_: Any? = nil) {
        NSLog("Join bookmark 4")
        joinBookmarkInternal(urlString: Defaults[.bookmarkMeetingURL4], service: Defaults[.bookmarkMeetingService4])
    }

    @objc
    func joinBookmark5(_: Any? = nil) {
        NSLog("Join bookmark 5")
        joinBookmarkInternal(urlString: Defaults[.bookmarkMeetingURL5], service: Defaults[.bookmarkMeetingService5])
    }

    @objc
    func joinBookmark(_: Any? = nil) {
        NSLog("Join bookmark")
        joinBookmarkInternal(urlString: Defaults[.bookmarkMeetingURL], service: Defaults[.bookmarkMeetingService])
    }

    @objc
    func joinNextMeeting(_: NSStatusBarButton? = nil) {
        if let nextEvent = statusBarItem.eventStore.getNextEvent(calendars: statusBarItem.calendars) {
            NSLog("Join next event")
            openEvent(nextEvent)
        } else {
            NSLog("No next event")
            sendNotification(title: "There are no next meetings today", text: "Woohoo! It's time to make cocoa", subtitle: "")
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
            _ = openLinkInDefaultBrowser(url)
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
