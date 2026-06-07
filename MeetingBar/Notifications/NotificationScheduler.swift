//
//  NotificationScheduler.swift
//  MeetingBar
//

import Foundation
import UserNotifications

/// Abstraction over `UNUserNotificationCenter` so the scheduler is testable
/// without involving the real notification center singleton.
protocol NotificationRequestSink: AnyObject, Sendable {
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(identifiers: [String])
}

@MainActor
protocol NotificationActionSink: AnyObject {
    func performNotificationAction(_ kind: NotificationKind, event: MBEvent) -> Bool
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
    nonisolated static let identifierPrefix = "mb-plan-"

    private let sink: NotificationRequestSink
    private let runner: NotificationActionRunner

    /// Delayed `Task`s for in-app actions (fullscreen / autoJoin / scriptOnStart),
    /// keyed by notification identifier. Reconciled on every refresh — stale
    /// tasks are cancelled, missing ones are scheduled.
    private var actionTasks: [String: Task<Void, Never>] = [:]
    private var isStopped = false

    init(
        sink: NotificationRequestSink = UNUserNotificationCenter.current(),
        actionSink: NotificationActionSink? = nil
    ) {
        self.sink = sink
        self.runner = NotificationActionRunner(actionSink: actionSink)
    }

    func setActionSink(_ actionSink: NotificationActionSink?) {
        runner.setActionSink(actionSink)
    }

    func stop() {
        isStopped = true
        actionTasks.values.forEach { $0.cancel() }
        actionTasks.removeAll()
        runner.setActionSink(nil)
    }

    func reconcile(
        events: [MBEvent],
        settings: NotificationPlanningSettings,
        now: Date = Date()
    ) async {
        guard !isStopped else { return }
        let planningEvents = events.map(NotificationPlanningEvent.init(event:))
        let plans =
            NotificationPlanner
            .plan(events: planningEvents, settings: settings, now: now)
        let systemPlans = plans.filter { $0.kind == .eventStart || $0.kind == .eventEnd }
        let actionPlans = plans.filter(\.kind.isInAppAction)

        reconcileActions(events: events, plans: actionPlans, settings: settings, now: now)

        let eventByID = Dictionary(
            events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let pending = await sink.pendingRequests()
        guard !isStopped else { return }
        let pendingMine =
            pending
            .filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
        let pendingByID = Dictionary(
            pendingMine.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let pendingSet = Set(pendingByID.keys)

        let desiredIDs = Set(systemPlans.map { Self.identifierPrefix + $0.identity })

        let stale = Array(pendingSet.subtracting(desiredIDs))
        if !stale.isEmpty {
            sink.removePending(identifiers: stale)
        }

        for plan in systemPlans {
            guard !isStopped else { return }
            guard let event = eventByID[plan.eventID] else { continue }
            let request = NotificationContent.request(
                for: plan, event: event, settings: settings, now: now)
            let identifier = request.identifier

            if let pendingRequest = pendingByID[identifier] {
                guard !hasSameContent(pendingRequest.content, request.content) else { continue }
                sink.removePending(identifiers: [identifier])
            }

            do {
                try await sink.add(request)
                guard !isStopped else { return }
            } catch {
                let errorDescription = String(describing: error)
                MeetingBarLogger.notifications.error(
                    "Could not add notification plan \(plan.identity, privacy: .private): \(errorDescription, privacy: .private)"
                )
            }
        }
    }

    private func hasSameContent(_ lhs: UNNotificationContent, _ rhs: UNNotificationContent) -> Bool {
        lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.body == rhs.body
            && lhs.categoryIdentifier == rhs.categoryIdentifier
            && lhs.threadIdentifier == rhs.threadIdentifier
            && lhs.interruptionLevel == rhs.interruptionLevel
            && NSDictionary(dictionary: lhs.userInfo).isEqual(to: rhs.userInfo)
    }

    // MARK: - In-app action scheduling

    /// Fire any due in-app actions immediately, then reconcile delayed-`Task`s
    /// against the desired action plan. Stale tasks are cancelled.
    private func reconcileActions(
        events: [MBEvent],
        plans: [PlannedNotification],
        settings: NotificationPlanningSettings,
        now: Date
    ) {
        runner.cleanupExpiredRecords(now: now)
        runner.fireDueActions(events: events, settings: settings, now: now)

        let eventByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let desiredIDs = Set(plans.map { Self.identifierPrefix + $0.identity })

        for id in Array(actionTasks.keys) where !desiredIDs.contains(id) {
            actionTasks[id]?.cancel()
            actionTasks[id] = nil
        }

        for plan in plans {
            let id = Self.identifierPrefix + plan.identity
            guard actionTasks[id] == nil, let event = eventByID[plan.eventID] else { continue }

            actionTasks[id] = Task { [weak self] in
                let delay = max(plan.fireDate.timeIntervalSince(now), 0)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.runner.fire(plan: plan, event: event, settings: settings, now: Date())
                    self.actionTasks[id] = nil
                }
            }
        }
    }
}

extension NotificationPlanningEvent {
    init(event: MBEvent) {
        self.init(
            id: event.id,
            lastModifiedDate: event.lastModifiedDate,
            startDate: event.startDate,
            endDate: event.endDate,
            status: event.status == .canceled ? .canceled : .active,
            participationStatus: event.participationStatus == .declined ? .declined : .active,
            isAllDay: event.isAllDay,
            hasMeetingLink: event.meetingLink != nil
        )
    }
}

// MARK: - Notification content building

/// Builds `UNNotificationRequest` objects from a planned notification.
/// Internal to the scheduler — not a public API.
private enum NotificationContent {
    static func request(
        for plan: PlannedNotification,
        event: MBEvent,
        settings: NotificationPlanningSettings,
        now: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = settings.hideMeetingTitle ? "general_meeting".loco() : event.title
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        content.userInfo = ["eventID": event.id]
        content.threadIdentifier = "meetingbar"

        switch plan.kind {
        case .eventStart:
            content.categoryIdentifier = EventNotificationIdentifiers.eventCategory
            content.body = settings.eventStartBody
        case .eventEnd:
            content.body = settings.eventEndBody
        case .fullscreen, .autoJoin, .scriptOnStart:
            content.body = ""
        }

        // Floor at 0.5s so the OS does not reject a too-immediate trigger.
        let interval = max(plan.fireDate.timeIntervalSince(now), 0.5)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(
            identifier: NotificationScheduler.identifierPrefix + plan.identity,
            content: content,
            trigger: trigger
        )
    }

    static func startBody(for offset: TimeBeforeEvent) -> String {
        switch offset {
        case .atStart: return "notifications_event_start_soon_body".loco()
        case .minuteBefore: return "notifications_event_start_one_minute_body".loco()
        case .threeMinuteBefore: return "notifications_event_start_three_minutes_body".loco()
        case .fiveMinuteBefore: return "notifications_event_start_five_minutes_body".loco()
        }
    }

    static func endBody(for offset: TimeBeforeEventEnd) -> String {
        switch offset {
        case .atEnd: return "notifications_event_ends_soon_body".loco()
        case .minuteBefore: return "notifications_event_ends_one_minute_body".loco()
        case .threeMinuteBefore: return "notifications_event_ends_three_minutes_body".loco()
        case .fiveMinuteBefore: return "notifications_event_ends_five_minutes_body".loco()
        }
    }
}

extension NotificationPlanningSettings {
    /// Snapshot of the per-action settings the scheduler currently owns.
    @MainActor
    static var currentForScheduler: NotificationPlanningSettings {
        let notif = AppSettings.current.notifications
        let adv = AppSettings.current.advanced
        let statusBar = AppSettings.current.statusBar
        let events = AppSettings.current.events
        return NotificationPlanningSettings(
            eventStart: .init(
                enabled: notif.joinEventNotification,
                offset: TimeInterval(notif.joinEventNotificationTime.rawValue)),
            eventEnd: .init(
                enabled: notif.endOfEventNotification,
                offset: TimeInterval(notif.endOfEventNotificationTime.rawValue)),
            fullscreen: .init(
                enabled: notif.fullscreenNotification,
                offset: TimeInterval(notif.fullscreenNotificationTime.rawValue)
            ),
            autoJoin: .init(
                enabled: adv.automaticEventJoin,
                offset: TimeInterval(adv.automaticEventJoinTime.rawValue)
            ),
            scriptOnStart: .init(
                enabled: adv.runEventStartScript && adv.eventStartScriptLocation != nil,
                offset: TimeInterval(adv.eventStartScriptTime.rawValue)
            ),
            dismissedEventIDs: Set(events.dismissedEvents.map(\.id)),
            fullscreenNotificationsForEventsWithoutMeetingLink:
                notif.fullscreenNotificationsForEventsWithoutMeetingLink,
            hideMeetingTitle: statusBar.hideMeetingTitle,
            eventStartBody: NotificationContent.startBody(
                for: notif.joinEventNotificationTime),
            eventEndBody: NotificationContent.endBody(for: notif.endOfEventNotificationTime)
        )
    }
}

extension EventActionEvent {
    fileprivate init(event: MBEvent) {
        self.init(
            id: event.id,
            lastModifiedDate: event.lastModifiedDate,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            hasMeetingLink: event.meetingLink != nil
        )
    }
}
