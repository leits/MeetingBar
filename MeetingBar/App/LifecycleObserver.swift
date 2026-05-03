//
//  LifecycleObserver.swift
//  MeetingBar
//

import AppKit
import Foundation

/// Registers for macOS system notifications (screen lock/unlock, wake,
/// timezone change, calendar day change) and forwards them as callbacks.
///
/// Owned by `AppDelegate`; keeps `AppDelegate` thin by concentrating all
/// `DistributedNotificationCenter` / `NSWorkspace` wiring here.
@MainActor
final class LifecycleObserver {
    var onScreenLocked: () -> Void = {}
    var onScreenUnlocked: () -> Void = {}
    var onDidWake: () -> Void = {}
    var onTimezoneChanged: () -> Void = {}
    var onDayChanged: () -> Void = {}

    private var observers: [Any] = []

    func start() {
        let dnc = DistributedNotificationCenter.default()

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onScreenLocked()
        })

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onScreenUnlocked()
        })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onDidWake()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onTimezoneChanged()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onDayChanged()
        })
    }

    func stop() {
        let dnc = DistributedNotificationCenter.default()
        for observer in observers {
            dnc.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
