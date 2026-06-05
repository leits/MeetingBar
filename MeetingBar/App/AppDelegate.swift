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
    var calendarSync: CalendarSync!
    let notificationScheduler = NotificationScheduler()
    let snoozeService = SnoozeService()
    let patronageService = PatronageService()
    private var notificationCenterDelegate: NotificationCenterDelegate?
    private var notificationActionHandler: NotificationActionHandler?
    private(set) var appModel: AppModel?
    private let lifecycleObserver = LifecycleObserver()
    private let urlHandler = URLHandler()
    private let windowCoordinator = WindowCoordinator()

    private var launchTask: Task<Void, Never>?
    private var notificationSetupTask: Task<Void, Never>?
    private var statusLoopTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_: Notification) {
        patronageService.start()

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

        launchTask = Task { [weak self] in
            guard let self else { return }
            let manager = await CalendarSync()
            guard !Task.isCancelled else {
                manager.stop()
                return
            }
            calendarSync = manager
            if Defaults[.onboardingCompleted] {
                setup()
            } else {
                windowCoordinator.openOnboardingWindow { [weak self] provider in
                    guard let self else {
                        return .failed("Application state is unavailable")
                    }
                    return await self.onboardingCompleted(with: provider)
                }
            }
            launchTask = nil
        }
    }

    func setup() {
        let env = AppEnvironment.live(
            calendarSync: calendarSync,
            notificationScheduler: notificationScheduler,
            snoozeService: snoozeService,
            openPreferences: { [weak self] in
                self?.openPreferencesWindow(nil)
            },
            resumeOAuthFlow: { [weak self] url in
                guard let calendarSync = self?.calendarSync else { return }
                calendarSync.repository.resumeAuthorizationFlow(with: url)
            }
        )
        let model = AppModel(environment: env)
        appModel = model
        AppRuntimeBridge.shared.install(appModel: model)

        let actionHandler = NotificationActionHandler(
            isScreenLocked: { [weak model] in model?.state.screenIsLocked ?? false },
            send: { [weak model] action in model?.send(action) },
            showFullscreen: { [weak self] event in
                self?.windowCoordinator.openFullscreenNotificationWindow(event: event)
            },
            runEventStartScript: { event in
                runMeetingStartsScript(event: event, type: .meetingStart)
            }
        )
        notificationActionHandler = actionHandler
        notificationScheduler.setActionSink(actionHandler)

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

        let ncDelegate = NotificationCenterDelegate { [weak model] response in
            model?.send(.notificationResponse(response))
        }
        notificationCenterDelegate = ncDelegate
        UNUserNotificationCenter.current().delegate = ncDelegate
        notificationSetupTask = Task { @MainActor [weak self] in
            await ensureNotificationAuthorization()
            guard !Task.isCancelled else { return }
            registerNotificationCategories()
            self?.notificationSetupTask = nil
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

    private func onboardingCompleted(
        with provider: EventStoreProvider
    ) async -> ProviderSelectionResult {
        if appModel == nil {
            setup()
            windowCoordinator.attachOnboardingAppModel(appModel)
        }
        guard let appModel else {
            return .failed("Application state is unavailable")
        }
        return await appModel.completeOnboarding(with: provider)
    }

    @objc
    func openChangelogWindow(_: NSStatusBarButton?) {
        windowCoordinator.openChangelogWindow()
    }

    @objc
    func openPreferencesWindow(_: NSStatusBarButton?) {
        windowCoordinator.openPreferencesWindow(
            appModel: appModel,
            calendarSync: calendarSync,
            patronageService: patronageService
        )
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
        launchTask?.cancel()
        launchTask = nil
        notificationSetupTask?.cancel()
        notificationSetupTask = nil
        statusLoopTask?.cancel()
        statusLoopTask = nil
        lifecycleObserver.stop()
        appModel?.handleWillTerminate()
        notificationScheduler.stop()
        calendarSync?.stop()
        patronageService.stop()
        cancellables.removeAll()
    }
}
