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

import PromiseKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusBarItem: StatusBarItemController!

    var selectedCalendarIDsObserver: DefaultsObservation?
    var showEventDetailsObserver: DefaultsObservation?
    var showMeetingServiceIconObserver: DefaultsObservation?

    var allDayEventsObserver: DefaultsObservation?
    var nonAllDayEventsObserver: DefaultsObservation?

    var statusbarEventTitleLengthObserver: DefaultsObservation?
    var timeFormatObserver: DefaultsObservation?
    var bookmarksObserver: DefaultsObservation?

    var eventTitleFormatObserver: DefaultsObservation?
    var eventTimeFormatObserver: DefaultsObservation?

    var eventTitleIconFormatObserver: DefaultsObservation?

    var shortenEventTitleObserver: DefaultsObservation?
    var menuEventTitleLengthObserver: DefaultsObservation?
    var meetingTitleVisibilityObserver: DefaultsObservation?
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
    var preferredLanguageObserver: DefaultsObservation?
    var showEventMaxTimeUntilEventThresholdObserver: DefaultsObservation?
    var showEventMaxTimeUntilEventEnabledObserver: DefaultsObservation?

    var preferencesWindow: NSWindow!
    var onboardingWindow: NSWindow!
    var changelogWindow: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handle(getURLEvent:replyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

        // AppStore sync
        completeStoreTransactions()
        checkAppSource()

        // Handle windows closing closing
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.windowClosed), name: NSWindow.willCloseNotification, object: nil)
        //

        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            Defaults[.appVersion] = appVersion
        }

        if GCEventStore.shared.isAuthed {
            setup()
        } else {
            Defaults[.selectedCalendarIDs] = []
            setup()
            _ = GCEventStore.shared.signIn().done {
                self.statusBarItem.loadCalendars()
            }
        }

//        if Defaults[.onboardingCompleted], GCEventStore.shared.isAuthed {
//            setup()
//        } else {
//            openOnboardingWindow()
//        }

        // When our main application starts, we have to kill
        // the auto launcher application if it's still running.
        postNotificationForAutoLauncher()
    }

    @objc
    func handle(getURLEvent event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor) {
        if let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           let url = URL(string: string)
        {
            GCEventStore.shared
                .currentAuthorizationFlow?.resumeExternalUserAgentFlow(with: url)
        }
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

    /**
     * tries to open the link from the macos system clipboard.
     */
    @objc
    func openLinkFromClipboard() {
        NSLog("Check macos clipboard for link")
        var clipboardContent = getClipboardContent()
        NSLog("Found \(clipboardContent) in clipboard")

        if !clipboardContent.isEmpty {
            let meetingLink = detectLink(&clipboardContent)

            if let meetingLink = meetingLink {
                openMeetingURL(meetingLink.service, meetingLink.url, nil)
            } else {
                let validUrl = NSURL(string: clipboardContent)
                if validUrl != nil {
                    URL(string: clipboardContent)?.openInDefaultBrowser()
                } else {
                    sendNotification("No valid url",
                                     "Clipboard has no meeting link, so the meeting cannot be started")
                }
            }
        } else {
            sendNotification("Clipboard is empty",
                             "Clipboard has no content, so the meeting cannot be started...")
        }
    }

    @objc
    func toggleMeetingTitleVisibility() {
        Defaults[.hideMeetingTitle].toggle()
    }

    @objc
    func refreshSources() {
//        TODO: fix refresh sources
//        statusBarItem.eventStore.refreshSourcesIfNecessary()
        statusBarItem.updateTitle()
        statusBarItem.updateMenu()
    }

    func setup() {
        statusBarItem = StatusBarItemController()
        statusBarItem.setAppDelegate(appdelegate: self)

        registerNotificationCategories()
        UNUserNotificationCenter.current().delegate = self

        statusBarItem.loadCalendars()

        scheduleUpdateStatusBarItem()
        scheduleFetchEvents()

        if Defaults[.browsers].isEmpty {
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

        KeyboardShortcuts.onKeyUp(for: .openClipboardShortcut) {
            self.openLinkFromClipboard()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleMeetingTitleVisibilityShortcut) {
            Defaults[.hideMeetingTitle].toggle()
        }

//        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.eventStoreChanged), name: .EKEventStoreChanged, object: statusBarItem.eventStore)

        showEventDetailsObserver = Defaults.observe(.showEventDetails) { change in
            if change.oldValue != change.newValue {
                NSLog("Change showEventDetails from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
        }

        shortenEventTitleObserver = Defaults.observe(.shortenEventTitle) { change in
            if change.oldValue != change.newValue {
                NSLog("Change shortenEventTitle from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
        }

        menuEventTitleLengthObserver = Defaults.observe(.menuEventTitleLength) { change in
            if change.oldValue != change.newValue {
                NSLog("Change menuEventTitleLengthObserver from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
        }

        meetingTitleVisibilityObserver = Defaults.observe(.hideMeetingTitle) { change in
            if change.oldValue != change.newValue {
                NSLog("Change hideMeetingTitle from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
                self.statusBarItem.updateTitle()

                // Reschedule next notification with updated event name visibility
                removePendingNotificationRequests()
                if let nextEvent = getNextEvent(events: self.statusBarItem.events) {
                    scheduleEventNotification(nextEvent)
                }
            }
        }

        showEventEndTimeObserver = Defaults.observe(.showEventEndTime) { change in
            if change.oldValue != change.newValue {
                NSLog("Change showEventEndTime from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
        }

        eventTimeFormatObserver = Defaults.observe(.eventTimeFormat) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed eventTimeFormat from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
                self.statusBarItem.updateTitle()
            }
        }

        statusbarEventTitleLengthObserver = Defaults.observe(.statusbarEventTitleLength) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed statusbarEventTitleLengthLimits from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
            }
        }

        disablePastEventObserver = Defaults.observe(.disablePastEvents) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed disablePastEvents from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
                self.statusBarItem.updateMenu()
            }
        }

        showPendingEventObserver = Defaults.observe(.showPendingEvents) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed showPendingEvents from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        }

        selectedCalendarIDsObserver = Defaults.observe(.selectedCalendarIDs) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed selectedCalendarIDs from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.loadCalendars()
            }
        }

        showMeetingServiceIconObserver = Defaults.observe(.showMeetingServiceIcon) { change in
            if change.oldValue != change.newValue {
                NSLog("Change showMeetingServiceIcon from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
        }

        allDayEventsObserver = Defaults.observe(.allDayEvents) { change in
            if change.oldValue != change.newValue {
                NSLog("Change allDayEvents from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        }

        nonAllDayEventsObserver = Defaults.observe(.nonAllDayEvents) { change in
            if change.oldValue != change.newValue {
                NSLog("Change nonAllDayEvents from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        }

        timeFormatObserver = Defaults.observe(.timeFormat) { change in
            if change.oldValue != change.newValue {
                NSLog("Change timeFormat from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
        }

        bookmarksObserver = Defaults.observe(keys: .bookmarks) {
            self.statusBarItem.updateMenu()
        }

        eventTitleFormatObserver = Defaults.observe(.eventTitleFormat) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed eventTitleFormat from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        }

        eventTitleIconFormatObserver = Defaults.observe(.eventTitleIconFormat) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed eventTitleFormat from \(String(describing: change.oldValue)) to \(String(describing: change.newValue))")
                self.statusBarItem.updateTitle()
            }
        }

        pastEventsAppereanceObserver = Defaults.observe(.pastEventsAppereance) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed pastEventsAppereance from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
        }
        declinedEventsAppereanceObserver = Defaults.observe(.declinedEventsAppereance) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed declinedEventsAppereance from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateMenu()
            }
        }
        personalEventsAppereanceObserver = Defaults.observe(.personalEventsAppereance) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed personalEventsAppereance from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        }
        showEventsForPeriodObserver = Defaults.observe(.showEventsForPeriod) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed showEventsForPeriod from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        }
        launchAtLoginObserver = Defaults.observe(.launchAtLogin) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed launchAtLogin from \(change.oldValue) to \(change.newValue)")
                SMLoginItemSetEnabled(AutoLauncher.bundleIdentifier as CFString, change.newValue)
            }
        }
        preferredLanguageObserver = Defaults.observe(.preferredLanguage) { change in
            if I18N.instance.changeLanguage(to: change.newValue) {
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        }
        joinEventNotificationObserver = Defaults.observe(.joinEventNotification) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed joinEventNotification from \(change.oldValue) to \(change.newValue)")
                if change.newValue == true {
                    if let nextEvent = getNextEvent(events: self.statusBarItem.events) {
                        scheduleEventNotification(nextEvent)
                    }
                } else {
                    removePendingNotificationRequests()
                }
            }
        }
        showEventMaxTimeUntilEventThresholdObserver = Defaults.observe(.showEventMaxTimeUntilEventThreshold) { change in
            if change.oldValue != change.newValue {
                NSLog("Changed showEventMaxTimeUntilEventThreshold from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
            }
        }
        showEventMaxTimeUntilEventEnabledObserver = Defaults.observe(.showEventMaxTimeUntilEventEnabled) { change in
            if change.oldValue != change.newValue {
                NSLog("Change showEventMaxTimeUntilEventEnabled from \(change.oldValue) to \(change.newValue)")
                self.statusBarItem.updateTitle()
            }
        }
    }

    @objc
    func windowClosed(notification: NSNotification) {
        let window = notification.object as? NSWindow
        if let windowTitle = window?.title {
            if windowTitle == WindowTitles.onboarding, !Defaults[.onboardingCompleted] {
                NSApplication.shared.terminate(self)
            } else if windowTitle == WindowTitles.changelog {
                Defaults[.lastRevisedVersionInChangelog] = Defaults[.appVersion]
                statusBarItem.updateMenu()
            }
        }
    }

    func getClipboardContent() -> String {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string) ?? ""
    }

//    @objc
//    func eventStoreChanged(_: NSNotification) {
//        NSLog("Store changed. Update status bar menu.")
//        statusBarItem.updateTitle()
//        statusBarItem.updateMenu()
//    }

    private func scheduleFetchEvents() {
        let timer = Timer(timeInterval: 60, target: self, selector: #selector(fetchEvents), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }

    private func scheduleUpdateStatusBarItem() {
        let timer = Timer(timeInterval: 5, target: self, selector: #selector(updateStatusBarItem), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }

    @objc
    private func fetchEvents() {
        NSLog("Firing reccuring fetchEvents")
        DispatchQueue.main.async {
            self.statusBarItem.loadCalendars()
            self.statusBarItem.loadEvents()
        }
    }

    @objc
    private func updateStatusBarItem() {
//        NSLog("Firing reccuring updateStatusBarItem")
        DispatchQueue.main.async {
            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
        }
    }

    /**
     * implementation is necessary to show notifications even when the app has focus!
     */
    func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])
    }

    internal func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "JOIN_ACTION", UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == "EVENT" {
                if let eventID = response.notification.request.content.userInfo["eventID"] {
                    // TODO: Allow to open event from any notification
                    // built-in method EKEventStore.event(withIdentifier:) is broken
                    // temporary allow to open only the last event
                    if let nextEvent = getNextEvent(events: statusBarItem.events) {
                        if nextEvent.eventIdentifier == (eventID as! String) {
                            NSLog("Join \(nextEvent.title) event from notication")
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
        let browser: Browser = Defaults[.browserForCreateMeeting]

        switch Defaults[.createMeetingService] {
        case .meet:
            openMeetingURL(MeetingServices.meet, CreateMeetingLinks.meet, browser)
        case .zoom:
            openMeetingURL(MeetingServices.zoom, CreateMeetingLinks.zoom, browser)
        case .teams:
            openMeetingURL(MeetingServices.teams, CreateMeetingLinks.teams, browser)
        case .jam:
            openMeetingURL(MeetingServices.jam, CreateMeetingLinks.jam, browser)
        case .coscreen:
            openMeetingURL(MeetingServices.coscreen, CreateMeetingLinks.coscreen, browser)
        case .gcalendar:
            openMeetingURL(nil, CreateMeetingLinks.gcalendar, browser)
        case .outlook_office365:
            openMeetingURL(nil, CreateMeetingLinks.outlook_office365, browser)
        case .outlook_live:
            openMeetingURL(nil, CreateMeetingLinks.outlook_live, browser)
        case .url:
            var url: String = Defaults[.createMeetingServiceUrl]
            let checkedUrl = NSURL(string: url)

            if !url.isEmpty, checkedUrl != nil {
                openMeetingURL(nil, URL(string: url)!, browser)
            } else {
                if !url.isEmpty {
                    url += " "
                }

                sendNotification("create_meeting_error_title".loco(), "create_meeting_error_message".loco(url))
            }
        }
    }

    @objc
    func joinBookmark(sender: NSMenuItem) {
        NSLog("Called to join bookmark")
        if let bookmark: Bookmark = sender.representedObject as? Bookmark {
            guard let url = URL(string: bookmark.url) else {
                return
            }
            NSLog("Bookmark url: \(bookmark.url)")
            openMeetingURL(bookmark.service, url, nil)
        }
    }

    @objc
    func joinNextMeeting(_: NSStatusBarButton? = nil) {
        if let nextEvent = getNextEvent(events: statusBarItem.events) {
            NSLog("Join next event")
            openEvent(nextEvent)
        } else {
            NSLog("No next event")
            sendNotification("next_meeting_empty_title".loco(), "next_meeting_empty_message".loco())
            return
        }
    }

    @objc
    func clickOnEvent(sender: NSMenuItem) {
        NSLog("Click on event (\(sender.title))!")
        let event: MBEvent = sender.representedObject as! MBEvent
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
    func copyEventMeetingLink(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            let eventTitle = event.title
            if let meeting = getMeetingLink(event) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(meeting.url.absoluteString, forType: .string)
            } else {
                sendNotification("status_bar_error_link_missed_title".loco(eventTitle), "status_bar_error_link_missed_message".loco())
            }
        }
    }

    @objc
    func emailAttendees(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            emailEventAttendees(event)
        }
    }

    /**
     * opens an event in the fantastical app. It uses the x-fantastical url handler which is not fully described on the fantastical website,
     * but was confirmed in the github ticket.
     */
    @objc
    func openEventInFantastical(sender: NSMenuItem) {
        if let eventWithDate: EventWithDate = sender.representedObject as? EventWithDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            let queryItems = [URLQueryItem(name: "date", value: dateFormatter.string(from: eventWithDate.dateSection)), URLQueryItem(name: "title", value: eventWithDate.event.title)]
            var fantasticalUrlComp = URLComponents()
            fantasticalUrlComp.scheme = "x-fantastical3"
            fantasticalUrlComp.host = "show"
            fantasticalUrlComp.queryItems = queryItems

            let fantasticalUrl = fantasticalUrlComp.url!
            fantasticalUrl.openInDefaultBrowser()
        }
    }

    @objc
    func openChangelogWindow(_: NSStatusBarButton?) {
        NSLog("Open changelof window")
        let contentView = ChangelogView()
        if changelogWindow != nil {
            changelogWindow.close()
        }
        changelogWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.closable, .titled, .resizable],
            backing: .buffered,
            defer: false
        )
        changelogWindow.title = WindowTitles.changelog
        changelogWindow.contentView = NSHostingView(rootView: contentView)
        changelogWindow.makeKeyAndOrderFront(nil)
        // allow the changelof window can be focused automatically when opened
        NSApplication.shared.activate(ignoringOtherApps: true)

        let controller = NSWindowController(window: changelogWindow)
        controller.showWindow(self)

        changelogWindow.center()
        changelogWindow.orderFrontRegardless()
    }

    @objc
    func openPrefecencesWindow(_: NSStatusBarButton?) {
        NSLog("Open preferences window")
        let contentView = PreferencesView()
        if preferencesWindow != nil {
            preferencesWindow.close()
        }
        preferencesWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 610),
            styleMask: [.closable, .titled, .resizable],
            backing: .buffered,
            defer: false
        )

        preferencesWindow.title = WindowTitles.preferences
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
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 450),
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false
        )

        onboardingWindow.title = WindowTitles.onboarding
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
