//
//  AppDelegate.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Defaults
import KeyboardShortcuts
import SwiftUI
import UserNotifications
import Combine

@MainActor
@main
class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    var statusBarItem: StatusBarItemController!
    var eventManager: EventManager!

    var screenIsLocked: Bool = false

    weak var preferencesWindow: NSWindow!
    private var defaultsWatchers = [Task<Void, Never>]()
    private var statusLoopTask: Task<Void, Never>?

    private var eventCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_: Notification) {
        // AppStore sync
        completeStoreTransactions()
        checkAppSource()

        // Handle windows closing closing
        NotificationCenter.default.addObserver(
            self, selector: #selector(AppDelegate.windowClosed),
            name: NSWindow.willCloseNotification, object: nil
        )
        //

        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            Defaults[.appVersion] = appVersion
        }

        statusBarItem = StatusBarItemController()

        if Defaults[.onboardingCompleted] {
            Task {
                eventManager = await EventManager()
                setup()

            }
        } else {
            openOnboardingWindow()
        }
    }

    func setup() {
        statusBarItem.setAppDelegate(appdelegate: self)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(AppDelegate.handleURLEvent(getURLEvent:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
          await ensureNotificationAuthorization()
          registerNotificationCategories()
        }

        eventCancellable = eventManager.$events
          .receive(on: DispatchQueue.main)          // ensure UI work on main thread
          .sink { [weak self] events in
            guard let self = self else { return }
            // 1) update your model
            self.statusBarItem.events = events
            // 2) redraw
            self.statusBarItem.updateTitle()
            self.statusBarItem.updateMenu()
            // 3) schedule next notification
            if let next = events.nextEvent() {
              Task { await scheduleEventNotification(next) }
            }
          }

        startAsyncLoops()
        // ActionsOnEventStart
        ActionsOnEventStart(self).startWatching()
        //

        if Defaults[.browsers].isEmpty {
            addInstalledBrowser()
        }

        // Handle sleep and wake up events
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            self, selector: #selector(AppDelegate.lockListener),
            name: .init("com.apple.screenIsLocked"), object: nil
        )
        dnc.addObserver(
            self, selector: #selector(AppDelegate.unlockListener),
            name: .init("com.apple.screenIsUnlocked"), object: nil
        )

        // Shortcuts
        KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut, action: createMeeting)

        KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
            Task { @MainActor in self.statusBarItem.joinNextMeeting()}
        }

        KeyboardShortcuts.onKeyUp(for: .openMenuShortcut) {
            Task { @MainActor in self.statusBarItem.openMenu()}
        }

        KeyboardShortcuts.onKeyUp(for: .openClipboardShortcut, action: openLinkFromClipboard)

        KeyboardShortcuts.onKeyUp(for: .toggleMeetingTitleVisibilityShortcut) {
            Defaults[.hideMeetingTitle].toggle()
        }

        // Settings change observers
        defaultsWatchers.append(
        Task {
            for await _ in Defaults.updates(
                [
                    .statusbarEventTitleLength, .eventTimeFormat,
                    .eventTitleIconFormat, .showEventMaxTimeUntilEventThreshold,
                    .showEventMaxTimeUntilEventEnabled, .showEventDetails,
                    .shortenEventTitle, .menuEventTitleLength,
                    .showEventEndTime, .showMeetingServiceIcon,
                    .timeFormat, .bookmarks, .eventTitleFormat,
                    .personalEventsAppereance, .pastEventsAppereance,
                    .declinedEventsAppereance
                ], initial: false
            ) {
                self.statusBarItem.updateTitle()
                self.statusBarItem.updateMenu()
            }
        })

        defaultsWatchers.append(
        Task {
            for await _ in Defaults.updates(.hideMeetingTitle, initial: false) {
                self.statusBarItem.updateMenu()
                self.statusBarItem.updateTitle()

                // Reschedule next notification with updated event name visibility
                removePendingNotificationRequests(withID: notificationIDs.event_starts)
                removePendingNotificationRequests(withID: notificationIDs.event_ends)
                if let nextEvent = self.statusBarItem.events.nextEvent() {
                    Task {
                        await scheduleEventNotification(nextEvent)
                    }
                }
            }
        })

        defaultsWatchers.append(
        Task {
            for await value in Defaults.updates(.preferredLanguage)
                where I18N.instance.changeLanguage(to: value) {
                    self.statusBarItem.updateTitle()
                    self.statusBarItem.updateMenu()
            }
        })

        defaultsWatchers.append(
        Task {
            for await value in Defaults.updates(.joinEventNotification, initial: false) {
                if value == true {
                    if let nextEvent = self.statusBarItem.events.nextEvent() {
                        Task {
                            await scheduleEventNotification(nextEvent)
                        }
                    }
                } else {
                    removePendingNotificationRequests(withID: notificationIDs.event_starts)
                }
            }
        })
    }

    /*
     * -----------------------
     * MARK: - Scheduled tasks
     * ------------------------
     */
    private func startAsyncLoops() {
        // Redraw status bar item on hh:mm:00
        statusLoopTask = Task.detached(priority: .utility) { [weak self] in
            while let self, !Task.isCancelled {
                // Compute now & next minute boundary
                let now = Date()
                let calendar = Calendar.current
                let nextMinute = calendar.nextDate(
                    after: now,
                    matching: DateComponents(second: 0),
                    matchingPolicy: .nextTime
                )!

                // Sleep until that boundary
                let interval = nextMinute.timeIntervalSince(now)
                try? await Task.sleep(nanoseconds: UInt64(interval * Double(NSEC_PER_SEC)))

                // Once we hit hh:mm:00, redraw
                await MainActor.run { self.updateStatusBarItem() }
            }
        }
    }

    /*
     * -----------------------
     * MARK: - User Notification Center
     * ------------------------
     */

    /// Implementation is necessary to show notifications even when the app has focus!
    func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) ->
            Void
    ) {
        completionHandler([.list, .banner, .badge, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
        }

        guard
            ["EVENT", "SNOOZE_EVENT"].contains(
                response.notification.request.content.categoryIdentifier),
            let eventID = response.notification.request.content.userInfo["eventID"] as? String,
            let event = statusBarItem.events.first(where: { $0.id == eventID })
        else {
            return
        }
        Task {
            switch response.actionIdentifier {
            case "JOIN_ACTION", UNNotificationDefaultActionIdentifier:
                event.openMeeting()
            case "DISMISS_ACTION":
                statusBarItem.dismiss(event: event)
            case NotificationEventTimeAction.untilStart.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.untilStart)
            case NotificationEventTimeAction.fiveMinuteLater.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.fiveMinuteLater)
            case NotificationEventTimeAction.tenMinuteLater.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.tenMinuteLater)
            case NotificationEventTimeAction.fifteenMinuteLater.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.fifteenMinuteLater)
            case NotificationEventTimeAction.thirtyMinuteLater.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.thirtyMinuteLater)
            default:
                break
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

    func openFullscreenNotificationWindow(event: MBEvent) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(
            rootView: FullscreenNotification(event: event, window: window))
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = .canJoinAllSpaces
        window.collectionBehavior = .moveToActiveSpace

        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.title = "Meetingbar Fullscreen Notification"
        window.level = .screenSaver

        let controller = NSWindowController(window: window)
        controller.showWindow(self)

        window.center()
        window.orderFrontRegardless()
    }

    @objc
    func openPreferencesWindow(_: NSStatusBarButton?) {
        let contentView = PreferencesView().environmentObject(eventManager)

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
    func handleURLEvent(
        getURLEvent event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor
    ) {
        if let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           let url = URL(string: string) {
            if url == URL(string: "meetingbar://preferences") {
                openPreferencesWindow(nil)
            } else {
                GCEventStore.shared
                    .currentAuthorizationFlow?.resumeExternalUserAgentFlow(with: url)
            }
        }
    }

    @objc
    func handleManualRefresh() {
      Task {
        do {
          try await eventManager.refreshSources()
        } catch {
            NSLog("Refresh Failed: \(error)")
        }
      }
    }

    @objc
    private func updateStatusBarItem() {
        self.statusBarItem.updateTitle()
        self.statusBarItem.updateMenu()
    }

    @objc
    func quit(_: NSStatusBarButton) {
        defaultsWatchers.forEach { $0.cancel() }
        statusLoopTask?.cancel()
        NSApplication.shared.terminate(self)
    }

    func applicationWillTerminate(_ notification: Notification) {
        defaultsWatchers.forEach { $0.cancel() }
        statusLoopTask?.cancel()
    }
}
