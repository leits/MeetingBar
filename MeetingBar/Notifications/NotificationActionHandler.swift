//
//  NotificationActionHandler.swift
//  MeetingBar
//

import Foundation

/// Executes scheduled in-app notification actions through their owning routes.
@MainActor
final class NotificationActionHandler: NotificationActionSink {
    private let isScreenLocked: () -> Bool
    private let send: (AppAction) -> Void
    private let showFullscreen: (MBEvent) -> Void
    private let runEventStartScript: (MBEvent) -> Void

    init(
        isScreenLocked: @escaping () -> Bool,
        send: @escaping (AppAction) -> Void,
        showFullscreen: @escaping (MBEvent) -> Void,
        runEventStartScript: @escaping (MBEvent) -> Void
    ) {
        self.isScreenLocked = isScreenLocked
        self.send = send
        self.showFullscreen = showFullscreen
        self.runEventStartScript = runEventStartScript
    }

    func performNotificationAction(_ kind: NotificationKind, event: MBEvent) -> Bool {
        guard !isScreenLocked() else { return false }

        switch kind {
        case .fullscreen:
            showFullscreen(event)
        case .autoJoin:
            send(.joinMeeting(eventID: event.id))
        case .scriptOnStart:
            runEventStartScript(event)
        case .eventStart, .eventEnd:
            return false
        }

        return true
    }
}
