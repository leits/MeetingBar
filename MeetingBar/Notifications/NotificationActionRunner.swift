//
//  NotificationActionRunner.swift
//  MeetingBar
//

import Foundation

/// Evaluates and fires in-app notification actions (fullscreen, auto-join, script on start)
/// for events that are due at the current moment.
///
/// The runner uses `NotificationRecordStore` to avoid double-firing and
/// `NotificationActionSink` to perform the actual side effect.
@MainActor
final class NotificationActionRunner {
    private let recordStore: NotificationRecordStore
    private weak var actionSink: NotificationActionSink?

    init(recordStore: NotificationRecordStore, actionSink: NotificationActionSink? = nil) {
        self.recordStore = recordStore
        self.actionSink = actionSink
    }

    func setActionSink(_ sink: NotificationActionSink?) {
        actionSink = sink
    }

    // MARK: - Record cleanup

    func cleanupExpiredRecords(now: Date) {
        recordStore.cleanupExpired(now: now)
    }

    // MARK: - Due action check

    /// Fire any in-app actions whose trigger time has already passed.
    func fireDueActions(
        events: [MBEvent],
        settings: NotificationPlanningSettings,
        now: Date
    ) {
        for event in events where shouldConsiderActionEvent(event, settings: settings) {
            for kind in NotificationKind.inAppActions {
                let action = actionSettings(for: kind, settings: settings)
                guard action.enabled else { continue }
                let plan = PlannedNotification(
                    eventID: event.id,
                    kind: kind,
                    fireDate: event.startDate.addingTimeInterval(-action.offset),
                    identity: ""
                )
                fireAction(plan: plan, event: event, action: action, now: now)
            }
        }
    }

    // MARK: - Scheduled action dispatch

    func fire(
        plan: PlannedNotification, event: MBEvent, settings: NotificationPlanningSettings, now: Date
    ) {
        let action = actionSettings(for: plan.kind, settings: settings)
        fireAction(plan: plan, event: event, action: action, now: now)
    }

    // MARK: - Private helpers

    private func fireAction(
        plan: PlannedNotification,
        event: MBEvent,
        action: NotificationPlanningSettings.Action,
        now: Date
    ) {
        guard let config = actionConfig(for: plan.kind, action: action),
            let decision = EventActionPolicy.evaluate(
                event: EventActionEvent(
                    id: event.id,
                    lastModifiedDate: event.lastModifiedDate,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    hasMeetingLink: event.meetingLink != nil
                ),
                config: config,
                processed: recordStore.processedRecords(for: plan.kind),
                now: now
            )
        else { return }

        if decision.shouldFireSideEffect {
            guard actionSink?.performNotificationAction(plan.kind, event: event) == true else {
                return
            }
        }

        recordStore.setProcessedRecords(decision.updatedProcessed, for: plan.kind)
    }

    private func actionSettings(
        for kind: NotificationKind,
        settings: NotificationPlanningSettings
    ) -> NotificationPlanningSettings.Action {
        switch kind {
        case .fullscreen:
            return settings.fullscreen
        case .autoJoin:
            return settings.autoJoin
        case .scriptOnStart:
            return settings.scriptOnStart
        case .eventStart, .eventEnd:
            return .disabled
        }
    }

    private func actionConfig(
        for kind: NotificationKind,
        action: NotificationPlanningSettings.Action
    ) -> EventActionConfig? {
        switch kind {
        case .fullscreen, .autoJoin:
            return EventActionConfig(
                actionTime: action.offset,
                allowsRecentlyStarted: true,
                requiresMeetingLink: true
            )
        case .scriptOnStart:
            return EventActionConfig(
                actionTime: action.offset,
                allowsRecentlyStarted: false,
                requiresMeetingLink: false
            )
        case .eventStart, .eventEnd:
            return nil
        }
    }

    private func shouldConsiderActionEvent(
        _ event: MBEvent,
        settings: NotificationPlanningSettings
    ) -> Bool {
        if settings.dismissedEventIDs.contains(event.id) { return false }
        if event.status == .canceled { return false }
        if event.participationStatus == .declined { return false }
        return true
    }
}

extension NotificationKind {
    static let inAppActions: [NotificationKind] = [
        .fullscreen, .autoJoin, .scriptOnStart,
    ]

    var isInAppAction: Bool {
        Self.inAppActions.contains(self)
    }
}
