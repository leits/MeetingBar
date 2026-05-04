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
    private let actionScheduler: NotificationActionScheduler

    init(
        sink: NotificationRequestSink = UNUserNotificationCenter.current(),
        recordStore: NotificationRecordStore = NotificationRecordStore(),
        actionSink: NotificationActionSink? = nil
    ) {
        self.sink = sink
        let runner = NotificationActionRunner(recordStore: recordStore, actionSink: actionSink)
        self.actionScheduler = NotificationActionScheduler(runner: runner)
    }

    func setActionSink(_ actionSink: NotificationActionSink?) {
        actionScheduler.setActionSink(actionSink)
    }

    func reconcile(
        events: [MBEvent],
        settings: NotificationPlanningSettings,
        now: Date = Date()
    ) async {
        let planningEvents = events.map(NotificationPlanningEvent.init(event:))
        let plans =
            NotificationPlanner
            .plan(events: planningEvents, settings: settings, now: now)
        let systemPlans = plans.filter { $0.kind == .eventStart || $0.kind == .eventEnd }
        let actionPlans = plans.filter(\.kind.isInAppAction)

        actionScheduler.reconcile(events: events, plans: actionPlans, settings: settings, now: now)

        let eventByID = Dictionary(
            events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let pending = await sink.pendingRequests()
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
            guard let event = eventByID[plan.eventID] else { continue }
            let request = NotificationContentFactory.request(for: plan, event: event, settings: settings, now: now)
            let identifier = request.identifier

            if let pendingRequest = pendingByID[identifier] {
                guard !hasSameContent(pendingRequest.content, request.content) else { continue }
                sink.removePending(identifiers: [identifier])
            }

            do {
                try await sink.add(request)
            } catch {
                NSLog("NotificationScheduler: failed to add \(plan.identity): \(error)")
            }
        }
    }

    private func hasSameContent(_ lhs: UNNotificationContent, _ rhs: UNNotificationContent) -> Bool
    {
        lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.body == rhs.body
            && lhs.categoryIdentifier == rhs.categoryIdentifier
            && lhs.threadIdentifier == rhs.threadIdentifier
            && lhs.interruptionLevel == rhs.interruptionLevel
            && NSDictionary(dictionary: lhs.userInfo).isEqual(to: rhs.userInfo)
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
            isAllDay: event.isAllDay
        )
    }
}

extension NotificationPlanningSettings {
    /// Snapshot of the per-action settings the scheduler currently owns.
    @MainActor
    static var currentForScheduler: NotificationPlanningSettings {
        let notif = SettingsStore.shared.settings.notifications
        let adv = SettingsStore.shared.settings.advanced
        let statusBar = SettingsStore.shared.settings.statusBar
        let events = SettingsStore.shared.settings.events
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
            hideMeetingTitle: statusBar.hideMeetingTitle,
            eventStartBody: NotificationContentFactory.startBody(for: notif.joinEventNotificationTime),
            eventEndBody: NotificationContentFactory.endBody(for: notif.endOfEventNotificationTime)
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
