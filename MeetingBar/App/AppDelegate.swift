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
        // When launched as a test host, skip the entire launch flow so tests
        // don't trigger onboarding, status bar setup, or calendar sync.
        guard !AppMessageCenter.shouldSuppressSystemUI() else { return }

        patronageService.start()

        // Migrate legacy per-provider browser keys → providerBrowsers map
        MeetingOpenPreferencesMigration.migrateDefaultsIfNeeded()
        StatusBarTitleFormatMigration.migrateDefaultsIfNeeded()

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
                setup(triggerInitialRefresh: false)
                presentOnboardingWindow()
            }
            launchTask = nil
        }
    }

    /// Opens the first-run setup window from the cold-launch path when setup is
    /// incomplete.
    func presentOnboardingWindow() {
        guard let appModel else { return }
        windowCoordinator.openOnboardingWindow(
            appModel: appModel,
            onProviderSelected: { [weak appModel] provider in
                guard let appModel else {
                    return .failed("Application state is unavailable")
                }
                return await appModel.changeProvider(to: provider)
            },
            onComplete: { [weak appModel] provider in
                guard let appModel else {
                    return .failed("Application state is unavailable")
                }
                let result = await appModel.completeOnboarding(with: provider)
                if result == .success {
                    appModel.handleLaunch()
                }
                return result
            }
        )
    }

    func setup(triggerInitialRefresh: Bool = true) {
        guard appModel == nil else { return }
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
            appState: { [weak model] in model?.state ?? AppState() },
            events: { [weak model] in model?.state.events ?? [] },
            send: { [weak model] action in model?.send(action) },
            openPreferences: { [weak self] in self?.openPreferencesWindow(nil) },
            openChangelog: { [weak self] in self?.openChangelogWindow(nil) },
            quit: { [weak self] in self?.quit(nil) }
        ))

        // Drive status bar from AppModel state: update title and menu whenever
        // events change.
        model.$state
            .removeDuplicates()
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
        lifecycleObserver.onSystemClockChanged = { [weak self] in
            self?.handleSystemClockChange()
        }
        lifecycleObserver.onTimezoneChanged = { [weak self] in
            self?.handleTimezoneChange()
        }
        lifecycleObserver.onDayChanged = { [weak self] in
            self?.appModel?.handleDayChange()
        }
        lifecycleObserver.start()

        if triggerInitialRefresh {
            model.handleLaunch()
        }
    }

    /*
     * -----------------------
     * MARK: - Scheduled tasks
     * ------------------------
     */
    private func startAsyncLoops() {
        statusLoopTask?.cancel()

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
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(max(interval, 0) * Double(NSEC_PER_SEC))
                    )
                } catch {
                    return
                }

                // Once we hit hh:mm:00, redraw
                await MainActor.run {
                    self.statusBarItem.updateTitle()
                    self.statusBarItem.updateMenu()
                }
            }
        }
    }

    private func handleSystemClockChange() {
        appModel?.handleSystemClockChange()
        startAsyncLoops()
    }

    private func handleTimezoneChange() {
        appModel?.handleTimezoneChange()
        startAsyncLoops()
    }

    /*
     * -----------------------
     * MARK: - Windows
     * ------------------------
     */

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
