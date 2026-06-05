//
//  AppDelegate.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import AppKit
import Combine
import Defaults
import KeyboardShortcuts
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
    private let windowCoordinator = WindowCoordinator()

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

        Task {
            eventManager = await EventManager()
            if Defaults[.onboardingCompleted] {
                setup()
            } else {
                windowCoordinator.openOnboardingWindow { [weak self] provider in
                    await self?.onboardingCompleted(with: provider)
                }
            }
        }
    }

    func setup() {
        notificationScheduler.setActionSink(self)

        let env = AppEnvironment.live(
            eventManager: eventManager,
            notificationScheduler: notificationScheduler,
            openPreferences: { [weak self] in
                self?.openPreferencesWindow(nil)
            },
            resumeOAuthFlow: { [weak self] url in
                guard let eventManager = self?.eventManager else { return }
                eventManager.repository.resumeAuthorizationFlow(with: url)
            }
        )
        let model = AppModel(environment: env)
        appModel = model
        AppRuntimeBridge.shared.install(appModel: model)

        statusBarItem.configure(dependencies: StatusBarDependencies(
            events: { [weak model] in model?.state.events ?? [] },
            send: { [weak model] action in model?.send(action) },
            openPreferences: { [weak self] in self?.openPreferencesWindow(nil) },
            openChangelog: { [weak self] in self?.openChangelogWindow(nil) },
            quit: { [weak self] in self?.quit(nil) }
        ))

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
            self?.appModel?.handleScreenLock()
        }
        lifecycleObserver.onScreenUnlocked = { [weak self] in
            self?.appModel?.handleScreenUnlock()
        }
        lifecycleObserver.onDidWake = { [weak self] in
            self?.appModel?.handleWake()
        }
        lifecycleObserver.onTimezoneChanged = { [weak self] in
            self?.appModel?.handleTimezoneChange()
        }
        lifecycleObserver.onDayChanged = { [weak self] in
            self?.appModel?.handleDayChange()
        }
        lifecycleObserver.start()

        // Kick off the initial refresh through the model.
        model.handleLaunch()
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

    private func onboardingCompleted(with provider: EventStoreProvider) async {
        setup()
        windowCoordinator.attachOnboardingAppModel(appModel)
        await appModel?.completeOnboarding(with: provider)
    }

    @objc
    func openChangelogWindow(_: NSStatusBarButton?) {
        windowCoordinator.openChangelogWindow()
    }

    func openFullscreenNotificationWindow(event: MBEvent) {
        windowCoordinator.openFullscreenNotificationWindow(event: event)
    }

    @objc
    func openPreferencesWindow(_: NSStatusBarButton?) {
        windowCoordinator.openPreferencesWindow(appModel: appModel, eventManager: eventManager)
    }

    @objc
    func windowClosed(notification: NSNotification) {
        let window = notification.object as? NSWindow
        windowCoordinator.handleWindowClosed(
            window,
            onboardingCompleted: Defaults[.onboardingCompleted],
            onIncompleteOnboardingClosed: { [weak self] in
                guard let self else { return }
                NSApplication.shared.terminate(self)
            },
            onChangelogClosed: { [weak self] in
                AppSettings.acknowledgeCurrentChangelog()
                self?.statusBarItem.updateMenu()
            }
        )
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
            appModel?.send(.openRoute(urlHandler.route(for: url)))
        }
    }

    @objc
    func quit(_: Any?) {
        statusLoopTask?.cancel()
        NSApplication.shared.terminate(self)
    }

    func applicationWillTerminate(_: Notification) {
        statusLoopTask?.cancel()
        appModel?.handleWillTerminate()
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
            MeetingOpener.open(event: event)
            return true
        case .scriptOnStart:
            runMeetingStartsScript(event: event, type: .meetingStart)
            return true
        case .eventStart, .eventEnd:
            return false
        }
    }
}
