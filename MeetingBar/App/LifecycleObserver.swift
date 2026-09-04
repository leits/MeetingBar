//
//  LifecycleObserver.swift
//  MeetingBar
//

import AppKit
import Foundation
import Network

/// Registers for macOS system notifications (screen lock/unlock, wake,
/// clock/timezone change, calendar day change, network reachability) and
/// forwards them as callbacks.
///
/// Owned by `AppDelegate`; keeps `AppDelegate` thin by concentrating all
/// `DistributedNotificationCenter` / `NSWorkspace` / `NWPathMonitor` wiring
/// here.
@MainActor
final class LifecycleObserver {
    var onScreenLocked: () -> Void = {}
    var onScreenUnlocked: () -> Void = {}
    var onDidWake: () -> Void = {}
    var onSystemClockChanged: () -> Void = {}
    var onTimezoneChanged: () -> Void = {}
    var onDayChanged: () -> Void = {}

    /// Fires on the transition from unusable to usable network.
    ///
    /// Wake fires before Wi-Fi reassociates or a VPN finishes connecting, so a
    /// wake-triggered refresh routinely runs with no route to the provider.
    /// Without this trigger the next attempt waits for the periodic timer, and
    /// the menu bar keeps showing the previous day's events in the meantime.
    var onNetworkBecameReachable: () -> Void = {}

    private var observers: [Any] = []
    private var pathMonitor: NWPathMonitor?
    /// `nil` until the first path update, so becoming reachable at launch does
    /// not duplicate the refresh that launch already triggers.
    private var isNetworkReachable: Bool?
    private var lastReachabilityCallback: Date?
    private var trailingReachabilityTask: Task<Void, Never>?
    /// Invalidates path updates from a superseded or stopped monitor. Clearing
    /// `pathUpdateHandler` cannot recall a handler invocation that already
    /// enqueued its main-actor hop, and two such updates (unsatisfied then
    /// satisfied) would otherwise reconstruct a transition after `stop()`.
    private var monitorGeneration = 0
    /// Floor between reachability-driven refreshes. A roaming Wi-Fi link or a
    /// reconnecting VPN can flap through several satisfied transitions in a
    /// row, and each one would otherwise cost a full calendarList plus a
    /// per-calendar events fetch.
    private static let reachabilityRefreshInterval: TimeInterval = 60

    func start() {
        startNetworkMonitor()

        let dnc = DistributedNotificationCenter.default()

        observers.append(
            dnc.addObserver(
                forName: .init("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onScreenLocked()
                }
            })

        observers.append(
            dnc.addObserver(
                forName: .init("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onScreenUnlocked()
                }
            })

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onDidWake()
                }
            })

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSSystemClockDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onSystemClockChanged()
                }
            })

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onTimezoneChanged()
                }
            })

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSCalendarDayChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onDayChanged()
                }
            })
    }

    func stop() {
        // Clear the handler before cancelling: a path update already dispatched
        // on the monitor queue would otherwise still enqueue its main-actor hop
        // and fire a refresh during teardown.
        pathMonitor?.pathUpdateHandler = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        monitorGeneration += 1
        isNetworkReachable = nil
        lastReachabilityCallback = nil
        trailingReachabilityTask?.cancel()
        trailingReachabilityTask = nil

        let dnc = DistributedNotificationCenter.default()
        for observer in observers {
            dnc.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func startNetworkMonitor() {
        pathMonitor?.pathUpdateHandler = nil
        pathMonitor?.cancel()
        trailingReachabilityTask?.cancel()
        trailingReachabilityTask = nil
        monitorGeneration += 1
        let generation = monitorGeneration
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, generation == self.monitorGeneration else { return }
                let wasReachable = self.isNetworkReachable
                self.isNetworkReachable = reachable
                guard reachable, wasReachable == false else { return }
                self.handleReachableTransition(generation: generation)
            }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
    }

    /// Fires the refresh immediately outside the throttle window, otherwise
    /// defers it to the end of that window.
    ///
    /// A flapping link must not cost one full fetch per transition, but it must
    /// also not swallow the transition that finally restored the connection —
    /// dropping that one strands the app on stale events until the periodic
    /// timer comes round, which is the delay this trigger exists to avoid.
    /// Deferring keeps at most one refresh in flight per window and always acts
    /// on the most recent transition.
    private func handleReachableTransition(generation: Int) {
        let now = Date()
        guard let last = lastReachabilityCallback else {
            lastReachabilityCallback = now
            onNetworkBecameReachable()
            return
        }

        let elapsed = now.timeIntervalSince(last)
        guard elapsed < Self.reachabilityRefreshInterval else {
            lastReachabilityCallback = now
            onNetworkBecameReachable()
            return
        }

        let remaining = Self.reachabilityRefreshInterval - elapsed
        trailingReachabilityTask?.cancel()
        trailingReachabilityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * Double(NSEC_PER_SEC)))
            guard let self,
                  !Task.isCancelled,
                  generation == self.monitorGeneration,
                  self.isNetworkReachable == true else { return }
            self.trailingReachabilityTask = nil
            self.lastReachabilityCallback = Date()
            self.onNetworkBecameReachable()
        }
    }
}
