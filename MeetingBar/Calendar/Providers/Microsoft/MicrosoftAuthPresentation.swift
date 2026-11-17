//
//  MicrosoftAuthPresentation.swift
//  MeetingBar
//
//  Provides the presentation anchor MSAL needs for ASWebAuthenticationSession.
//
//  MSAL requires an `NSViewController` whose view is attached to a window to
//  anchor the system sign-in sheet. MeetingBar is an `LSUIElement` accessory
//  app with no main window, and `WindowCoordinator` builds its windows from a
//  bare `NSHostingView` (no `contentViewController`). So the Microsoft store
//  owns a small dedicated window purely to host the anchor. It also shows a
//  "continue in your browser" affordance with a Cancel button while the sheet
//  is up.
//

import AppKit
import SwiftUI

@MainActor
final class MicrosoftAuthPresentationAnchor {
    private var window: NSWindow?

    /// Presents the anchor window and returns the view controller MSAL should
    /// attach its ASWebAuthenticationSession to. `onCancel` fires if the user
    /// clicks Cancel in the waiting window.
    func present(onCancel: @escaping () -> Void) -> NSViewController {
        if let existing = window?.contentViewController {
            return existing
        }

        let hosting = NSHostingController(
            rootView: MicrosoftSignInWaitingView(onCancel: onCancel)
        )

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "onboarding_authorization_microsoft_window_title".loco()
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        positionOverActiveWindowOrCenter(panel)

        // Accessory apps are not frontmost by default; activate before keying
        // so the sign-in sheet appears in front (mirrors
        // WindowCoordinator.openPreferencesWindow).
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        window = panel
        return hosting
    }

    /// Closes and releases the sign-in anchor window.
    func dismiss() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        window = nil
    }

    /// Centers the panel over a visible Preferences/Onboarding window, or on screen when none is open.
    private func positionOverActiveWindowOrCenter(_ panel: NSWindow) {
        let anchorWindow = NSApp.windows.first { candidate in
            candidate.isVisible
                && (candidate.title == WindowTitles.preferences
                    || candidate.title == WindowTitles.onboarding)
        }

        guard let anchorWindow else {
            panel.center()
            return
        }

        let anchorFrame = anchorWindow.frame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: anchorFrame.midX - panelSize.width / 2,
            y: anchorFrame.midY - panelSize.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

private struct MicrosoftSignInWaitingView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.small)
            Text("onboarding_authorization_microsoft_waiting".loco())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("general_cancel".loco(), role: .cancel, action: onCancel)
        }
        .padding(24)
        // NSWindow.contentViewController resizes the window to the hosting view's
        // fitting size, ignoring the contentRect above, so the view must carry
        // an explicit width or the text wraps one character per line.
        .frame(width: 380)
    }
}
