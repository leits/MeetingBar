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
    static let identifierPrefix = "mb-plan-"

    private let sink: NotificationRequestSink
    private weak var actionSink: NotificationActionSink?
    private var actionTasks: [String: Task<Void, Never>] = [:]

    init(
        sink: NotificationRequestSink = UNUserNotificationCenter.current(),
        actionSink: NotificationActionSink? = nil
    ) {
        self.sink = sink
        self.actionSink = actionSink
    }

    func setActionSink(_ actionSink: NotificationActionSink?) {
        self.actionSink = actionSink
    }

    func reconcile(
        events: [MBEvent],
        settings: NotificationPlanningSettings,
        now: Date = Date()
    ) async {
        let planningEvents = events.map(NotificationPlanningEvent.init(event:))
        let plans =
            NotificationPlanningPolicy
            .plan(events: planningEvents, settings: settings, now: now)
        let systemPlans = plans.filter { $0.kind == .eventStart || $0.kind == .eventEnd }
        let actionPlans = plans.filter(\.kind.isInAppAction)

        let eventByID = Dictionary(
            events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        cleanupExpiredActionRecords(now: now)
        if actionSink != nil {
            fireDueActions(events: events, settings: settings, now: now)
        }
        reconcileActionTasks(actionPlans, eventByID: eventByID, settings: settings, now: now)

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
            let request = buildRequest(for: plan, event: event, settings: settings, now: now)
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

    private func reconcileActionTasks(
        _ plans: [PlannedNotification],
        eventByID: [String: MBEvent],
        settings: NotificationPlanningSettings,
        now: Date
    ) {
        guard actionSink != nil else {
            cancelAllActionTasks()
            return
        }

        let desiredIDs = Set(plans.map { Self.identifierPrefix + $0.identity })
        for id in Array(actionTasks.keys) where !desiredIDs.contains(id) {
            actionTasks[id]?.cancel()
            actionTasks[id] = nil
        }

        for plan in plans {
            let id = Self.identifierPrefix + plan.identity
            guard actionTasks[id] == nil,
                let event = eventByID[plan.eventID]
            else { continue }

            let action = actionSettings(for: plan.kind, settings: settings)
            actionTasks[id] = Task { [weak self] in
                let delay = max(plan.fireDate.timeIntervalSince(now), 0)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.fireAction(plan: plan, event: event, action: action, now: Date())
                    self.actionTasks[id] = nil
                }
            }
        }
    }

    private func cancelAllActionTasks() {
        for task in actionTasks.values {
            task.cancel()
        }
        actionTasks.removeAll()
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

    private func fireAction(
        plan: PlannedNotification,
        event: MBEvent,
        action: NotificationPlanningSettings.Action,
        now: Date
    ) {
        guard let config = actionConfig(for: plan.kind, action: action),
            let decision = EventActionPolicy.evaluate(
                event: EventActionEvent(event: event),
                config: config,
                processed: processedActionRecords(for: plan.kind),
                now: now
            )
        else { return }

        if decision.shouldFireSideEffect {
            guard actionSink?.performNotificationAction(plan.kind, event: event) == true else {
                return
            }
        }

        setProcessedActionRecords(decision.updatedProcessed, for: plan.kind)
    }

    private func fireDueActions(
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

    private func shouldConsiderActionEvent(
        _ event: MBEvent,
        settings: NotificationPlanningSettings
    ) -> Bool {
        if settings.dismissedEventIDs.contains(event.id) { return false }
        if event.status == .canceled { return false }
        if event.participationStatus == .declined { return false }
        return true
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

    private func cleanupExpiredActionRecords(now: Date) {
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

    private func processedActionRecords(for kind: NotificationKind) -> [EventActionProcessedEvent] {
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

    private func setProcessedActionRecords(
        _ records: [EventActionProcessedEvent],
        for kind: NotificationKind
    ) {
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

    private func buildRequest(
        for plan: PlannedNotification, event: MBEvent, settings: NotificationPlanningSettings,
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
            content.categoryIdentifier = "EVENT"
            content.body = settings.eventStartBody
        case .eventEnd:
            content.body = settings.eventEndBody
        case .fullscreen, .autoJoin, .scriptOnStart:
            // In-app actions are handled before request construction.
            content.body = ""
        }

        // Floor at 0.5s so the OS does not reject a too-immediate trigger.
        let interval = max(plan.fireDate.timeIntervalSince(now), 0.5)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(
            identifier: Self.identifierPrefix + plan.identity,
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
            eventStartBody: NotificationScheduler.startBody(for: notif.joinEventNotificationTime),
            eventEndBody: NotificationScheduler.endBody(for: notif.endOfEventNotificationTime)
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

extension EventActionProcessedEvent {
    fileprivate init(processedEvent: ProcessedEvent) {
        self.init(
            id: processedEvent.id,
            lastModifiedDate: processedEvent.lastModifiedDate,
            eventEndDate: processedEvent.eventEndDate
        )
    }

    fileprivate var processedEvent: ProcessedEvent {
        ProcessedEvent(
            id: id,
            lastModifiedDate: lastModifiedDate,
            eventEndDate: eventEndDate
        )
    }
}

extension Array where Element == ProcessedEvent {
    fileprivate var actionRecords: [EventActionProcessedEvent] {
        map(EventActionProcessedEvent.init(processedEvent:))
    }
}

extension Array where Element == EventActionProcessedEvent {
    fileprivate var processedEvents: [ProcessedEvent] {
        map(\.processedEvent)
    }
}

extension NotificationKind {
    fileprivate static let inAppActions: [NotificationKind] = [
        .fullscreen, .autoJoin, .scriptOnStart,
    ]

    fileprivate var isInAppAction: Bool {
        Self.inAppActions.contains(self)
    }
}
