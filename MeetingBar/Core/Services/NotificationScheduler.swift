//
//  NotificationScheduler.swift
//  MeetingBar
//

import Defaults
import Foundation
import UserNotifications

/// Abstraction over `UNUserNotificationCenter` so the scheduler is testable
/// without involving the real notification center singleton.
protocol NotificationRequestSink: AnyObject, Sendable {
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(identifiers: [String])
}

extension UNUserNotificationCenter: @unchecked @retroactive Sendable {}
extension UNNotificationRequest: @unchecked @retroactive Sendable {}

extension UNUserNotificationCenter: NotificationRequestSink {
    func pendingRequests() async -> [UNNotificationRequest] {
        await pendingNotificationRequests()
    }

    func removePending(identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Reconciles the desired notification plan (from `NotificationPlanningPolicy`)
/// with the system's pending notification queue:
///
/// * pending notifications with our `mb-plan-` prefix that are no longer in
///   the plan are removed,
/// * plans that are not yet pending are scheduled.
///
/// Identifiers belonging to other subsystems — in particular the snooze flow,
/// which still posts to the legacy `notificationIDs.event_starts` identifier —
/// are not touched, so the two paths can coexist.
@MainActor
final class NotificationScheduler {
    static let identifierPrefix = "mb-plan-"

    private let sink: NotificationRequestSink

    init(sink: NotificationRequestSink = UNUserNotificationCenter.current()) {
        self.sink = sink
    }

    func reconcile(
        events: [MBEvent],
        settings: NotificationPlanningSettings,
        now: Date = Date()
    ) async {
        let plans = NotificationPlanningPolicy
            .plan(events: events, settings: settings, now: now)
            .filter { $0.kind == .eventStart || $0.kind == .eventEnd }

        let eventByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let pending = await sink.pendingRequests()
        let pendingMine = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        let pendingSet = Set(pendingMine)

        let desiredIDs = Set(plans.map { Self.identifierPrefix + $0.identity })

        let stale = Array(pendingSet.subtracting(desiredIDs))
        if !stale.isEmpty {
            sink.removePending(identifiers: stale)
        }

        for plan in plans where !pendingSet.contains(Self.identifierPrefix + plan.identity) {
            guard let event = eventByID[plan.eventID] else { continue }
            let request = buildRequest(for: plan, event: event)
            do {
                try await sink.add(request)
            } catch {
                NSLog("NotificationScheduler: failed to add \(plan.identity): \(error)")
            }
        }
    }

    private func buildRequest(for plan: PlannedNotification, event: MBEvent) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = Defaults[.hideMeetingTitle] ? "general_meeting".loco() : event.title
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        content.userInfo = ["eventID": event.id]
        content.threadIdentifier = "meetingbar"

        switch plan.kind {
        case .eventStart:
            content.categoryIdentifier = "EVENT"
            content.body = Self.startBody(for: Defaults[.joinEventNotificationTime])
        case .eventEnd:
            content.body = Self.endBody(for: Defaults[.endOfEventNotificationTime])
        case .fullscreen, .autoJoin, .scriptOnStart:
            // Not handled by NotificationScheduler yet; ActionsOnEventStart
            // still owns these. NotificationPlanningPolicy filters them above.
            content.body = ""
        }

        // Floor at 0.5s so the OS does not reject a too-immediate trigger.
        let interval = max(plan.fireDate.timeIntervalSinceNow, 0.5)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(
            identifier: Self.identifierPrefix + plan.identity,
            content: content,
            trigger: trigger
        )
    }

    private static func startBody(for offset: TimeBeforeEvent) -> String {
        switch offset {
        case .atStart: return "notifications_event_start_soon_body".loco()
        case .minuteBefore: return "notifications_event_start_one_minute_body".loco()
        case .threeMinuteBefore: return "notifications_event_start_three_minutes_body".loco()
        case .fiveMinuteBefore: return "notifications_event_start_five_minutes_body".loco()
        }
    }

    private static func endBody(for offset: TimeBeforeEventEnd) -> String {
        switch offset {
        case .atEnd: return "notifications_event_ends_soon_body".loco()
        case .minuteBefore: return "notifications_event_ends_one_minute_body".loco()
        case .threeMinuteBefore: return "notifications_event_ends_three_minutes_body".loco()
        case .fiveMinuteBefore: return "notifications_event_ends_five_minutes_body".loco()
        }
    }
}

extension NotificationPlanningSettings {
    /// Snapshot of the per-action settings the scheduler currently owns —
    /// system event-start and event-end notifications. Fullscreen / auto-join
    /// / on-start script remain on the existing `ActionsOnEventStart` timer
    /// path until they are migrated, so they are surfaced as `.disabled` here
    /// to keep `NotificationPlanningPolicy` from emitting plans the scheduler
    /// would not act on.
    static var currentForScheduler: NotificationPlanningSettings {
        let startOffset = TimeInterval(Defaults[.joinEventNotificationTime].rawValue)
        let endOffset = TimeInterval(Defaults[.endOfEventNotificationTime].rawValue)
        return NotificationPlanningSettings(
            eventStart: .init(enabled: Defaults[.joinEventNotification], offset: startOffset),
            eventEnd: .init(enabled: Defaults[.endOfEventNotification], offset: endOffset),
            fullscreen: .disabled,
            autoJoin: .disabled,
            scriptOnStart: .disabled,
            dismissedEventIDs: Set(Defaults[.dismissedEvents].map(\.id))
        )
    }
}
