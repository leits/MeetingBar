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

    var preferredLanguageObserver: DefaultsObservation?

    var meetingTitleVisibilityObserver: DefaultsObservation?
    var joinEventNotificationObserver: DefaultsObservation?

    var eventFiltersObserver: DefaultsObservation?
    var calendarsObserver: DefaultsObservation?
    var appearanceSettingsObserver: DefaultsObservation?

    var screenIsLocked: Bool = false

    weak var preferencesWindow: NSWindow!

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
        // ActionsOnEventStart
        ActionsOnEventStart(self).startWatching()
        //

        if Defaults[.browsers].isEmpty {
            addInstalledBrowser()
        }

        // Backward compatibility for user defaults changes
        maintainDefaultsBackwardCompatibility()
        //

        // Handle sleep and wake up events
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(AppDelegate.lockListener), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(AppDelegate.unlockListener), name: .init("com.apple.screenIsUnlocked"), object: nil)

        // Shortcuts
        KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut, action: createMeeting)

        KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
            self.statusBarItem.joinNextMeeting()
        }

        KeyboardShortcuts.onKeyUp(for: .openMenuShortcut) {
            self.statusBarItem.openMenu()
        }

        KeyboardShortcuts.onKeyUp(for: .openClipboardShortcut, action: openLinkFromClipboard)

        KeyboardShortcuts.onKeyUp(for: .toggleMeetingTitleVisibilityShortcut) {
            Defaults[.hideMeetingTitle].toggle()
        }

        // Settings change observers
        appearanceSettingsObserver = Defaults.observe(
            keys: .statusbarEventTitleLength, .eventTimeFormat,
            .eventTitleIconFormat, .showEventMaxTimeUntilEventThreshold,
            .showEventMaxTimeUntilEventEnabled, .showEventDetails,
            .shortenEventTitle, .menuEventTitleLength,
            .showEventEndTime, .showMeetingServiceIcon,
            .timeFormat, .bookmarks, .eventTitleFormat,
            options: []
        ) {
            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
        }

        meetingTitleVisibilityObserver = Defaults.observe(.hideMeetingTitle, options: []) { change in
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
        eventFiltersObserver = Defaults.observe(
            keys: .showEventsForPeriod, .personalEventsAppereance,
            .disablePastEvents, .pastEventsAppereance,
            .declinedEventsAppereance, .showPendingEvents,
            .showTentativeEvents,
            .allDayEvents, .nonAllDayEvents, .customRegexes,
            options: []
        ) {
            self.statusBarItem.loadEvents()
        }

        calendarsObserver = Defaults.observe(keys: .selectedCalendarIDs, options: []) {
            self.statusBarItem.loadCalendars()
        }

        preferredLanguageObserver = Defaults.observe(.preferredLanguage) { change in
            if I18N.instance.changeLanguage(to: change.newValue) {
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        }
        joinEventNotificationObserver = Defaults.observe(.joinEventNotification, options: []) { change in
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

    func setEventStoreProvider(provider: EventStoreProvider) {
        Defaults[.eventStoreProvider] = provider
        switch provider {
        case .macOSEventKit:
            eventStore = EKEventStore.shared

            NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.eventStoreChanged), name: .EKEventStoreChanged, object: EKEventStore.shared)
            NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        case .googleCalendar:
            eventStore = GCEventStore.shared

            NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: EKEventStore.shared)
            NSAppleEventManager.shared().setEventHandler(self,
                                                         andSelector: #selector(handleURLEvent(getURLEvent:replyEvent:)),
                                                         forEventClass: AEEventClass(kInternetEventClass),
                                                         andEventID: AEEventID(kAEGetURL))
        }
    }

    /*
     * -----------------------
     * MARK: - Scheduled tasks
     * ------------------------
     */

    private func scheduleFetchEvents() {
        let timer = Timer(timeInterval: 60, target: self, selector: #selector(fetchEvents), userInfo: nil, repeats: true)
        timer.tolerance = 3
        RunLoop.current.add(timer, forMode: .common)
    }

    private func scheduleUpdateStatusBarItem() {
        let timer = Timer(timeInterval: 5, target: self, selector: #selector(updateStatusBarItem), userInfo: nil, repeats: true)
        timer.tolerance = 0.5
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
            if response.notification.request.content.categoryIdentifier == "EVENT" || response.notification.request.content.categoryIdentifier == "SNOOZE_EVENT" {
                if let eventID = response.notification.request.content.userInfo["eventID"] as? String {
                    if let event = statusBarItem.events.first(where: { $0.ID == eventID }) {
                        event.openMeeting()
                    }
                }
            }
        case NotificationEventTimeAction.untilStart.rawValue:
            handleSnoozeEvent(response, NotificationEventTimeAction.untilStart)
        case NotificationEventTimeAction.fiveMinuteLater.rawValue:
            handleSnoozeEvent(response, NotificationEventTimeAction.fiveMinuteLater)
        case NotificationEventTimeAction.tenMinuteLater.rawValue:
            handleSnoozeEvent(response, NotificationEventTimeAction.tenMinuteLater)
        case NotificationEventTimeAction.fifteenMinuteLater.rawValue:
            handleSnoozeEvent(response, NotificationEventTimeAction.fifteenMinuteLater)
        case NotificationEventTimeAction.thirtyMinuteLater.rawValue:
            handleSnoozeEvent(response, NotificationEventTimeAction.thirtyMinuteLater)
        default:
            break
        }

        completionHandler()
    }

    func handleSnoozeEvent(_ response: UNNotificationResponse, _ action: NotificationEventTimeAction) {
        if response.notification.request.content.categoryIdentifier == "EVENT" || response.notification.request.content.categoryIdentifier == "SNOOZE_EVENT" {
            if let eventID = response.notification.request.content.userInfo["eventID"] as? String {
                if let event = statusBarItem.events.first(where: { $0.ID == eventID }) {
                    snoozeEventNotification(event, action)
                }
            }
        }
    }

    /*
     * -----------------------
     * MARK: - Windows
     * ------------------------
     */

    func openOnboardingWindow() {
        let contentView = OnboardingView()
        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 450),
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false
        )

        onboardingWindow.title = WindowTitles.onboarding
        onboardingWindow.contentView = NSHostingView(rootView: contentView)
        let controller = NSWindowController(window: onboardingWindow)
        controller.showWindow(self)

        onboardingWindow.level = .floating
        onboardingWindow.center()
        onboardingWindow.orderFrontRegardless()
    }

    @objc
    func openChangelogWindow(_: NSStatusBarButton?) {
        let contentView = ChangelogView()
        let changelogWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.closable, .titled, .resizable],
            backing: .buffered,
            defer: false
        )
        changelogWindow.title = WindowTitles.changelog
        changelogWindow.level = .floating
        changelogWindow.contentView = NSHostingView(rootView: contentView)
        changelogWindow.makeKeyAndOrderFront(nil)
        // allow the changelof window can be focused automatically when opened
        NSApplication.shared.activate(ignoringOtherApps: true)

        let controller = NSWindowController(window: changelogWindow)
        controller.showWindow(self)

        changelogWindow.center()
        changelogWindow.orderFrontRegardless()
    }

    func openAutJoinWindow(event: MBEvent) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(rootView: AutoJoinScreen(event: event, window: window))
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = .canJoinAllSpaces
        window.collectionBehavior = .moveToActiveSpace

        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.title = "Meetingbar Autojoin"
        window.level = .screenSaver

        let controller = NSWindowController(window: window)
        controller.showWindow(self)

        window.center()
        window.orderFrontRegardless()
    }

    @objc
    func openPrefecencesWindow(_: NSStatusBarButton?) {
        let contentView = PreferencesView()

        if let preferencesWindow {
            // if a window is already open, focus on it instead of opening another one.
            NSApplication.shared.activate(ignoringOtherApps: true)
            preferencesWindow.makeKeyAndOrderFront(nil)
            return
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
                styleMask: [.closable, .titled, .resizable],
                backing: .buffered,
                defer: false
            )

            window.title = WindowTitles.preferences
            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            window.level = .floating
            // allow the preference window can be focused automatically when opened
            NSApplication.shared.activate(ignoringOtherApps: true)

            let controller = NSWindowController(window: window)
            controller.showWindow(self)

            window.center()
            window.orderFrontRegardless()

            preferencesWindow = window
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

    @objc
    func lockListener(notification _: NSNotification) {
        screenIsLocked = true
    }

    @objc
    func unlockListener(notification _: NSNotification) {
        screenIsLocked = false
    }

    /*
     * -----------------------
     * MARK: - Actions
     * ------------------------
     */

    @objc
    func handleURLEvent(getURLEvent event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor) {
        if let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           let url = URL(string: string) {
            if url == URL(string: "meetingbar://preferences") {
                openPrefecencesWindow(nil)
            } else {
                GCEventStore.shared
                    .currentAuthorizationFlow?.resumeExternalUserAgentFlow(with: url)
            }
        }
    }

    @objc
    func eventStoreChanged(_: NSNotification) {
        if statusBarItem == nil {
            return
        }
        DispatchQueue.main.async {
            self.statusBarItem.loadEvents()
        }
    }

    @objc
    private func fetchEvents() {
        DispatchQueue.main.async {
            self.statusBarItem.loadEvents()
        }
    }

    @objc
    private func updateStatusBarItem() {
        DispatchQueue.main.async {
            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
        }
    }

    @objc
    func quit(_: NSStatusBarButton) {
        NSApplication.shared.terminate(self)
    }
}
