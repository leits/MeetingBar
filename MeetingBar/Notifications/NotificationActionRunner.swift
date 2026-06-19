//
//  NotificationActionRunner.swift
//  MeetingBar
//

import Defaults
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

    init(recordStore: NotificationRecordStore = NotificationRecordStore(), actionSink: NotificationActionSink? = nil) {
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
                fireAction(
                    plan: plan,
                    event: event,
                    action: action,
                    settings: settings,
                    now: now
                )
            }
        }
    }

    // MARK: - Scheduled action dispatch

    func fire(
        plan: PlannedNotification, event: MBEvent, settings: NotificationPlanningSettings, now: Date
    ) {
        let action = actionSettings(for: plan.kind, settings: settings)
        fireAction(plan: plan, event: event, action: action, settings: settings, now: now)
    }

    // MARK: - Private helpers

    private func fireAction(
        plan: PlannedNotification,
        event: MBEvent,
        action: NotificationPlanningSettings.Action,
        settings: NotificationPlanningSettings,
        now: Date
    ) {
        let actionEvent = EventActionEvent(
            id: event.id,
            lastModifiedDate: event.lastModifiedDate,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            hasMeetingLink: event.meetingLink != nil
        )

        if plan.kind == .fullscreen {
            guard FullscreenNotificationEligibilityPolicy.isEligible(
                hasMeetingLink: actionEvent.hasMeetingLink,
                isAllDay: actionEvent.isAllDay,
                fullscreenNotificationsEnabled: action.enabled,
                includesEventsWithoutMeetingLink:
                    settings.fullscreenNotificationsForEventsWithoutMeetingLink
            ) else { return }
        }

        guard let config = actionConfig(for: plan.kind, action: action),
            let decision = EventActionPolicy.evaluate(
                event: actionEvent,
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
        case .fullscreen:
            return EventActionConfig(
                actionTime: action.offset,
                allowsRecentlyStarted: true,
                requiresMeetingLink: false
            )
        case .autoJoin:
            return EventActionConfig(
                actionTime: action.offset,
                allowsRecentlyStarted: true,
                requiresMeetingLink: true
            )
        case .scriptOnStart:
            return EventActionConfig(
                actionTime: action.offset,
                allowsRecentlyStarted: false,
                requiresMeetingLink: true
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
        .fullscreen, .autoJoin, .scriptOnStart
    ]

    var isInAppAction: Bool {
        Self.inAppActions.contains(self)
    }
}

// MARK: - Processed-event record persistence

/// Owns read/write access to the persisted processed-event records that track
/// which in-app notification actions have already fired.
///
/// Centralising these Defaults reads and writes makes the runner testable
/// without touching `UserDefaults` and isolates the persistence format from
/// the action-firing logic.
@MainActor
final class NotificationRecordStore {
    // MARK: - Cleanup

    func cleanupExpired(now: Date) {
        Defaults[.processedEventsForFullscreenNotification] =
            EventActionPolicy.cleanupExpired(
                Defaults[.processedEventsForFullscreenNotification].actionRecords,
                now: now
            ).processedEvents
        Defaults[.processedEventsForAutoJoin] =
            EventActionPolicy.cleanupExpired(
                Defaults[.processedEventsForAutoJoin].actionRecords,
                now: now
            ).processedEvents
        Defaults[.processedEventsForRunScriptOnEventStart] =
            EventActionPolicy.cleanupExpired(
                Defaults[.processedEventsForRunScriptOnEventStart].actionRecords,
                now: now
            ).processedEvents
    }

    // MARK: - Read

    func processedRecords(for kind: NotificationKind) -> [EventActionProcessedEvent] {
        switch kind {
        case .fullscreen:
            return Defaults[.processedEventsForFullscreenNotification].actionRecords
        case .autoJoin:
            return Defaults[.processedEventsForAutoJoin].actionRecords
        case .scriptOnStart:
            return Defaults[.processedEventsForRunScriptOnEventStart].actionRecords
        case .eventStart, .eventEnd:
            return []
        }
    }

    // MARK: - Write

    func setProcessedRecords(_ records: [EventActionProcessedEvent], for kind: NotificationKind) {
        switch kind {
        case .fullscreen:
            Defaults[.processedEventsForFullscreenNotification] = records.processedEvents
        case .autoJoin:
            Defaults[.processedEventsForAutoJoin] = records.processedEvents
        case .scriptOnStart:
            Defaults[.processedEventsForRunScriptOnEventStart] = records.processedEvents
        case .eventStart, .eventEnd:
            break
        }
    }
}

// MARK: - ProcessedEvent bridging

extension EventActionProcessedEvent {
    init(processedEvent: ProcessedEvent) {
        self.init(
            id: processedEvent.id,
            lastModifiedDate: processedEvent.lastModifiedDate,
            eventEndDate: processedEvent.eventEndDate
        )
    }

    var processedEvent: ProcessedEvent {
        ProcessedEvent(
            id: id,
            lastModifiedDate: lastModifiedDate,
            eventEndDate: eventEndDate
        )
    }
}

extension Array where Element == ProcessedEvent {
    var actionRecords: [EventActionProcessedEvent] {
        map(EventActionProcessedEvent.init(processedEvent:))
    }
}

extension Array where Element == EventActionProcessedEvent {
    var processedEvents: [ProcessedEvent] {
        map(\.processedEvent)
    }
}
