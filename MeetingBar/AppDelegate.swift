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
    var eventStore: EventStore!

    var eventStoreProviderObserver: DefaultsObservation?
    var selectedCalendarIDsObserver: DefaultsObservation?

    var launchAtLoginObserver: DefaultsObservation?
    var preferredLanguageObserver: DefaultsObservation?

    var meetingTitleVisibilityObserver: DefaultsObservation?
    var joinEventNotificationObserver: DefaultsObservation?

    var appearanceSettingsObserver: DefaultsObservation?

    var preferencesWindow: NSWindow!
    var onboardingWindow: NSWindow!
    var changelogWindow: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        // AppStore sync
        completeStoreTransactions()
        checkAppSource()

        // Handle windows closing closing
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.windowClosed), name: NSWindow.willCloseNotification, object: nil)
        //

        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            Defaults[.appVersion] = appVersion
        }

        if Defaults[.onboardingCompleted] {
            setEventStoreProvider(provider: Defaults[.eventStoreProvider])
            setup()
        } else {
            openOnboardingWindow()
        }

        // When our main application starts, we have to kill
        // the auto launcher application if it's still running.
        postNotificationForAutoLauncher()
    }

    /// Sending a notification to AutoLauncher app about main application running status
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
        statusBarItem = StatusBarItemController()
        statusBarItem.setAppDelegate(appdelegate: self)

        registerNotificationCategories()
        UNUserNotificationCenter.current().delegate = self

        _ = eventStore.signIn().done {
            self.statusBarItem.loadCalendars()
        }

        scheduleUpdateStatusBarItem()
        scheduleFetchEvents()

        if Defaults[.browsers].isEmpty {
            addInstalledBrowser()
        }

        // Shortcuts
        KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut, action: createMeeting)

        KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
            self.statusBarItem.joinNextMeeting()
        }

        KeyboardShortcuts.onKeyUp(for: .openMenuShortcut) {
            // show the menu as normal
            self.statusBarItem.statusItem.menu = self.statusBarItem.statusItemMenu
            self.statusBarItem.statusItem.button?.performClick(nil) // ...and click
        }

        KeyboardShortcuts.onKeyUp(for: .openClipboardShortcut, action: openLinkFromClipboard)

        KeyboardShortcuts.onKeyUp(for: .toggleMeetingTitleVisibilityShortcut) {
            Defaults[.hideMeetingTitle].toggle()
        }

        // Settings change observers
        appearanceSettingsObserver = Defaults.observe(keys: .statusbarEventTitleLength, .eventTimeFormat, .eventTitleIconFormat, .showEventMaxTimeUntilEventThreshold, .showEventMaxTimeUntilEventEnabled, .showEventDetails, .shortenEventTitle, .menuEventTitleLength, .showEventEndTime, .disablePastEvents, .showMeetingServiceIcon, .timeFormat, .bookmarks, .pastEventsAppereance, .declinedEventsAppereance, .showPendingEvents, .allDayEvents, .nonAllDayEvents, .eventTitleFormat, .personalEventsAppereance, .showEventsForPeriod) {
            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
        }

        meetingTitleVisibilityObserver = Defaults.observe(.hideMeetingTitle) { change in
            if change.oldValue != change.newValue {
                self.statusBarItem.updateMenu()
                self.statusBarItem.updateTitle()

                // Reschedule next notification with updated event name visibility
                removePendingNotificationRequests()
                if let nextEvent = getNextEvent(events: self.statusBarItem.events) {
                    scheduleEventNotification(nextEvent)
                }
            }
        }
        launchAtLoginObserver = Defaults.observe(.launchAtLogin) { change in
            if change.oldValue != change.newValue {
                SMLoginItemSetEnabled(AutoLauncher.bundleIdentifier as CFString, change.newValue)
            }
        }
        selectedCalendarIDsObserver = Defaults.observe(.selectedCalendarIDs) { change in
            if change.oldValue != change.newValue {
                self.statusBarItem.loadCalendars()
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
                if change.newValue == true {
                    if let nextEvent = getNextEvent(events: self.statusBarItem.events) {
                        scheduleEventNotification(nextEvent)
                    }
                } else {
                    removePendingNotificationRequests()
                }
            }
        }
    }

    func setEventStoreProvider(provider: eventStoreProvider) {
        Defaults[.eventStoreProvider] = provider
        switch provider {
        case .MacOSEventKit:
            eventStore = EKEventStore.shared

            NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.eventStoreChanged), name: .EKEventStoreChanged, object: EKEventStore.shared)
            NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        case .GoogleCalendar:
            eventStore = GCEventStore.shared

            NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: EKEventStore.shared)
            NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(getURLEvent:replyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        }
    }

    /*
     * -----------------------
     * MARK: - Scheduled tasks
     * ------------------------
     */

    private func scheduleFetchEvents() {
        let timer = Timer(timeInterval: 60, target: self, selector: #selector(fetchEvents), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }

    private func scheduleUpdateStatusBarItem() {
        let timer = Timer(timeInterval: 5, target: self, selector: #selector(updateStatusBarItem), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }

    /*
     * -----------------------
     * MARK: - User Notification Center
     * ------------------------
     */

    /// Implementation is necessary to show notifications even when the app has focus!
    func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "JOIN_ACTION", UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == "EVENT" {
                if let eventID = response.notification.request.content.userInfo["eventID"] {
                    // TODO: Allow to open event from any notification
                    // built-in method EKEventStore.event(withIdentifier:) is broken
                    // temporary allow to open only the last event
                    if let nextEvent = getNextEvent(events: statusBarItem.events) {
                        if nextEvent.ID == (eventID as! String) {
                            NSLog("Join \(nextEvent.title) event from notication")
                            nextEvent.openMeeting()
                        }
                    }
                }
            }
        default:
            break
        }

        completionHandler()
    }

    /*
     * -----------------------
     * MARK: - Windows
     * ------------------------
     */

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

    /*
     * -----------------------
     * MARK: - Actions
     * ------------------------
     */

    @objc
    func handleURLEvent(getURLEvent event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor) {
        if let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           let url = URL(string: string)
        {
            GCEventStore.shared
                .currentAuthorizationFlow?.resumeExternalUserAgentFlow(with: url)
        }
    }

    @objc
    func eventStoreChanged(_: NSNotification) {
        NSLog("Store changed. Update status bar menu.")
        DispatchQueue.main.async {
            self.statusBarItem?.updateTitle()
            self.statusBarItem?.updateMenu()
        }
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
        NSLog("Firing reccuring updateStatusBarItem")
        DispatchQueue.main.async {
            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
        }
    }

    @objc
    func quit(_: NSStatusBarButton) {
        NSLog("User click Quit")
        NSApplication.shared.terminate(self)
    }
}
