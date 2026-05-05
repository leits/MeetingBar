//
//  AppDelegate.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import UserNotifications

@MainActor
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: StatusBarItemController!
    var eventManager: EventManager!
    let notificationScheduler = NotificationScheduler()
    private var notificationCenterDelegate: NotificationCenterDelegate?
    private(set) var appModel: AppModel?
    private let lifecycleObserver = LifecycleObserver()
    private let urlHandler = URLHandler()

    weak var preferencesWindow: NSWindow!
    private weak var onboardingHandler: OnboardingHandler?
    private var statusLoopTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_: Notification) {
        // AppStore sync
        completeStoreTransactions()
        checkAppSource()

        // Migrate legacy per-provider browser keys → providerBrowsers map
        MeetingOpenPreferencesMigration.migrateDefaultsIfNeeded()

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

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(AppDelegate.handleURLEvent(getURLEvent:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

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
        notificationScheduler.setActionSink(self)

        let env = AppEnvironment.live(
            eventManager: eventManager,
            notificationScheduler: notificationScheduler
        )
        let model = AppModel(environment: env)
        appModel = model

        // Drive status bar from AppModel state: update title and menu whenever
        // events change.
        model.$state
            .map(\.events)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusBarItem.updateTitle()
                self?.statusBarItem.updateMenu()
            }
            .store(in: &cancellables)

        let ncDelegate = NotificationCenterDelegate(
            eventProvider: { [weak self] id in
                self?.appModel?.state.events.first { $0.id == id }
            },
            dismissHandler: { [weak self] event in self?.statusBarItem.dismiss(event: event) }
        )
        notificationCenterDelegate = ncDelegate
        UNUserNotificationCenter.current().delegate = ncDelegate
        Task { @MainActor in
            await ensureNotificationAuthorization()
            registerNotificationCategories()
        }

        startAsyncLoops()
        if Defaults[.browsers].isEmpty {
            addInstalledBrowser()
        }

        lifecycleObserver.onScreenLocked = { [weak self] in
            self?.appModel?.send(.screenLocked)
        }
        lifecycleObserver.onScreenUnlocked = { [weak self] in
            self?.appModel?.send(.screenUnlocked)
        }
        lifecycleObserver.onDidWake = { [weak self] in
            self?.appModel?.send(.didWake)
        }
        lifecycleObserver.onTimezoneChanged = { [weak self] in
            self?.appModel?.send(.timezoneChanged)
        }
        lifecycleObserver.onDayChanged = { [weak self] in
            self?.appModel?.send(.dayChanged)
        }
        lifecycleObserver.start()

        urlHandler.onOpenPreferences = { [weak self] in self?.openPreferencesWindow(nil) }
        urlHandler.onOAuthCallback = { [weak self] url in
            self?.eventManager.repository.resumeAuthorizationFlow(with: url)
        }

        // Kick off the initial refresh through the model.
        model.send(.launched)
    }

    /*
     * -----------------------
     * MARK: - Scheduled tasks
     * ------------------------
     */
    private func startAsyncLoops() {
        // Redraw status bar item on hh:mm:00
        statusLoopTask = Task(priority: .utility) { [weak self] in
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
                await MainActor.run {
                    self.statusBarItem.updateTitle()
                    self.statusBarItem.updateMenu()
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
        let handler = OnboardingHandler { [weak self] provider in
            await self?.onboardingCompleted(with: provider)
        }
        onboardingHandler = handler
        let contentView = OnboardingView().environmentObject(handler)
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

    private func onboardingCompleted(with provider: EventStoreProvider) async {
        eventManager = await EventManager()
        Defaults[.onboardingCompleted] = true
        setup()
        onboardingHandler?.appModel = appModel
        await eventManager.changeEventStoreProvider(provider)
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
        guard let appModel else { return }
        let contentView = PreferencesView().environmentObject(appModel)

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
            urlHandler.handle(url: url)
        }
    }

    @objc
    func quit(_: NSStatusBarButton) {
        statusLoopTask?.cancel()
        NSApplication.shared.terminate(self)
    }

    func applicationWillTerminate(_: Notification) {
        statusLoopTask?.cancel()
        appModel?.send(.willTerminate)
    }
}

extension AppDelegate: NotificationActionSink {
    func performNotificationAction(_ kind: NotificationKind, event: MBEvent) -> Bool {
        guard !(appModel?.state.screenIsLocked ?? false) else { return false }

        switch kind {
        case .fullscreen:
            openFullscreenNotificationWindow(event: event)
            return true
        case .autoJoin:
            event.openMeeting()
            return true
        case .scriptOnStart:
            runMeetingStartsScript(event: event, type: .meetingStart)
            return true
        case .eventStart, .eventEnd:
            return false
        }
    }
}
