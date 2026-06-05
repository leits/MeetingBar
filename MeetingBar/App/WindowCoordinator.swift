//
//  WindowCoordinator.swift
//  MeetingBar
//

import AppKit
import SwiftUI

/// Owns AppKit window lifecycle for app-level windows.
///
/// Behavior stays outside this type: callers provide closures for close-time
/// decisions such as terminating after incomplete onboarding or marking the
/// changelog as read.
@MainActor
final class WindowCoordinator {
    private weak var preferencesWindow: NSWindow?
    private weak var onboardingHandler: OnboardingHandler?

    func openOnboardingWindow(
        completion: @escaping @MainActor (EventStoreProvider) async -> Void
    ) {
        let handler = OnboardingHandler { provider in
            await completion(provider)
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

    func attachOnboardingAppModel(_ appModel: AppModel?) {
        onboardingHandler?.appModel = appModel
    }

    func openChangelogWindow() {
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

    func openPreferencesWindow(
        appModel: AppModel?,
        calendarSync: CalendarSync?,
        patronageService: PatronageService
    ) {
        guard let appModel, let calendarSync else { return }
        let contentView = PreferencesView(patronageService: patronageService)
            .environmentObject(appModel)
            .environmentObject(calendarSync)

        if let preferencesWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            preferencesWindow.makeKeyAndOrderFront(nil)
            return
        }

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
        NSApplication.shared.activate(ignoringOtherApps: true)

        let controller = NSWindowController(window: window)
        controller.showWindow(self)

        window.center()
        window.orderFrontRegardless()

        preferencesWindow = window
    }

    func handleWindowClosed(
        _ window: NSWindow?,
        onboardingCompleted: Bool,
        onIncompleteOnboardingClosed: () -> Void,
        onChangelogClosed: () -> Void
    ) {
        handleWindowClosed(
            title: window?.title,
            onboardingCompleted: onboardingCompleted,
            onIncompleteOnboardingClosed: onIncompleteOnboardingClosed,
            onChangelogClosed: onChangelogClosed
        )
    }

    func handleWindowClosed(
        title windowTitle: String?,
        onboardingCompleted: Bool,
        onIncompleteOnboardingClosed: () -> Void,
        onChangelogClosed: () -> Void
    ) {
        guard let windowTitle else { return }

        if windowTitle == WindowTitles.onboarding, !onboardingCompleted {
            onIncompleteOnboardingClosed()
        } else if windowTitle == WindowTitles.changelog {
            onChangelogClosed()
        }
    }
}
