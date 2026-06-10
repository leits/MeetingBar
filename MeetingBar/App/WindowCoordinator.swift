//
//  WindowCoordinator.swift
//  MeetingBar
//

import AppKit
import SwiftUI

enum FullscreenNotificationScreenSelectionPolicy {
    static func select<Screen>(
        keyWindowScreen: Screen?,
        mainWindowScreen: Screen?,
        mouseScreen: Screen?,
        mainScreen: Screen?,
        screens: [Screen]
    ) -> Screen? {
        keyWindowScreen ?? mainWindowScreen ?? mouseScreen ?? mainScreen ?? screens.first
    }
}

enum FullscreenNotificationKeyboardPolicy {
    static let escapeKeyCode: UInt16 = 53

    static func shouldDismiss(keyCode: UInt16) -> Bool {
        keyCode == escapeKeyCode
    }
}

final class FullscreenNotificationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if FullscreenNotificationKeyboardPolicy.shouldDismiss(keyCode: event.keyCode) {
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private enum WindowStylePolicy {
    @MainActor
    static func applyRoundedCorners(to window: NSWindow, radius: CGFloat = 12) {
        window.isOpaque = false
        window.backgroundColor = .white

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = radius
            contentView.layer?.masksToBounds = true
        }
    }
}

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
        appModel: AppModel,
        onProviderSelected:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult,
        onComplete:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult
    ) {
        let handler = OnboardingHandler(
            onProviderSelected: onProviderSelected,
            onComplete: onComplete
        )
        handler.appModel = appModel
        onboardingHandler = handler
        let contentView = OnboardingView().environmentObject(handler)
        let onboardingWindow = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [],
            backing: .buffered,
            defer: false
        )

        onboardingWindow.title = WindowTitles.onboarding
        onboardingWindow.contentView = NSHostingView(rootView: contentView)
        WindowStylePolicy.applyRoundedCorners(to: onboardingWindow)
        let controller = NSWindowController(window: onboardingWindow)
        controller.showWindow(self)

        onboardingWindow.level = .floating
        onboardingWindow.center()
        onboardingWindow.makeKeyAndOrderFront(nil)
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
        WindowStylePolicy.applyRoundedCorners(to: changelogWindow)
        changelogWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let controller = NSWindowController(window: changelogWindow)
        controller.showWindow(self)

        changelogWindow.center()
    }

    func openFullscreenNotificationWindow(event: MBEvent) {
        let screens = NSScreen.screens
        let mouseScreen = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let screen = FullscreenNotificationScreenSelectionPolicy.select(
            keyWindowScreen: NSApp.keyWindow?.screen,
            mainWindowScreen: NSApp.mainWindow?.screen,
            mouseScreen: mouseScreen,
            mainScreen: NSScreen.main,
            screens: screens
        )
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        let window = FullscreenNotificationWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(
            rootView: FullscreenNotification(event: event, window: window))
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = .moveToActiveSpace

        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.title = "Meetingbar Fullscreen Notification"
        window.level = .screenSaver

        let controller = NSWindowController(window: window)
        controller.showWindow(self)

        window.setFrame(screenFrame, display: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.closable, .titled, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = WindowTitles.preferences
        window.contentView = NSHostingView(rootView: contentView)
        WindowStylePolicy.applyRoundedCorners(to: window)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let controller = NSWindowController(window: window)
        controller.showWindow(self)

        window.center()

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
