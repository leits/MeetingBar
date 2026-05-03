//
//  NotificationActionScheduler.swift
//  MeetingBar
//

import Foundation

/// Manages the lifecycle of delayed Task objects that fire in-app actions
/// (fullscreen, auto-join, script on start) at their planned time.
///
/// The scheduler holds a map of running `Task`s keyed by notification
/// identifier and reconciles them against the current plan on each refresh,
/// cancelling stale tasks and creating new ones.
///
/// Actual action execution is delegated to `NotificationActionRunner`.
@MainActor
final class NotificationActionScheduler {
    private let runner: NotificationActionRunner
    private var actionTasks: [String: Task<Void, Never>] = [:]

    init(runner: NotificationActionRunner) {
        self.runner = runner
    }

    func setActionSink(_ sink: NotificationActionSink?) {
        runner.setActionSink(sink)
    }

    /// Fire any in-app actions that are already due, then schedule tasks for
    /// future ones.
    func reconcile(
        events: [MBEvent],
        plans: [PlannedNotification],
        settings: NotificationPlanningSettings,
        now: Date
    ) {
        runner.cleanupExpiredRecords(now: now)
        runner.fireDueActions(events: events, settings: settings, now: now)

        let eventByID = Dictionary(
            events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        reconcileTasks(plans, eventByID: eventByID, settings: settings, now: now)
    }

    func cancelAll() {
        for task in actionTasks.values { task.cancel() }
        actionTasks.removeAll()
    }

    // MARK: - Private

    private func reconcileTasks(
        _ plans: [PlannedNotification],
        eventByID: [String: MBEvent],
        settings: NotificationPlanningSettings,
        now: Date
    ) {
        let desiredIDs = Set(plans.map { NotificationScheduler.identifierPrefix + $0.identity })
        for id in Array(actionTasks.keys) where !desiredIDs.contains(id) {
            actionTasks[id]?.cancel()
            actionTasks[id] = nil
        }

        for plan in plans {
            let id = NotificationScheduler.identifierPrefix + plan.identity
            guard actionTasks[id] == nil,
                let event = eventByID[plan.eventID]
            else { continue }

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
