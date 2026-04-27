//
//  NotificationPlanningPolicy.swift
//  MeetingBar
//

import Foundation

/// Categories of per-event reminders MeetingBar can produce.
enum NotificationKind: String, CaseIterable, Equatable {
    case eventStart    // system notification before the event begins
    case eventEnd      // system notification before the event ends
    case fullscreen    // fullscreen overlay window
    case autoJoin      // automatically open the meeting URL
    case scriptOnStart // run the user-configured AppleScript
}

/// A single concrete reminder the scheduler should reconcile to the OS.
///
/// `identity` is the stable key the scheduler uses to deduplicate against
/// already-pending requests. Two `PlannedNotification` values with the same
/// `identity` are considered the same scheduled action even if `fireDate`
/// drifts (e.g. across calendar refreshes).
struct PlannedNotification: Equatable {
    let eventID: String
    let kind: NotificationKind
    let fireDate: Date
    let identity: String
}

struct NotificationPlanningSettings: Equatable {
    struct Action: Equatable {
        let enabled: Bool
        /// Seconds before the reference moment (start or end). 0 = at the moment.
        let offset: TimeInterval

        static let disabled = Action(enabled: false, offset: 0)
    }

    let eventStart: Action
    let eventEnd: Action
    let fullscreen: Action
    let autoJoin: Action
    let scriptOnStart: Action
    let dismissedEventIDs: Set<String>
}

enum NotificationPlanningPolicy {
    /// Returns the list of reminders that should be live for the given events
    /// at `now`. Output is sorted ascending by `fireDate`.
    ///
    /// All-day events are deliberately not planned: timed system notifications
    /// at midnight are not useful, and the runtime is responsible for firing
    /// fullscreen / auto-join / script for an all-day event while `now` lies
    /// inside the event range. The runtime layer can read the same `events`
    /// list directly for that case.
    static func plan(
        events: [MBEvent],
        settings: NotificationPlanningSettings,
        now: Date
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []

        for event in events where shouldConsider(event: event, dismissed: settings.dismissedEventIDs) {
            appendIfDue(.eventStart, anchor: event.startDate, action: settings.eventStart, event: event, now: now, into: &planned)
            appendIfDue(.eventEnd, anchor: event.endDate, action: settings.eventEnd, event: event, now: now, into: &planned)
            appendIfDue(.fullscreen, anchor: event.startDate, action: settings.fullscreen, event: event, now: now, into: &planned)
            appendIfDue(.autoJoin, anchor: event.startDate, action: settings.autoJoin, event: event, now: now, into: &planned)
            appendIfDue(.scriptOnStart, anchor: event.startDate, action: settings.scriptOnStart, event: event, now: now, into: &planned)
        }

        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    private static func shouldConsider(event: MBEvent, dismissed: Set<String>) -> Bool {
        if dismissed.contains(event.id) { return false }
        if event.status == .canceled { return false }
        if event.participationStatus == .declined { return false }
        if event.isAllDay { return false }
        return true
    }

    private static func appendIfDue(
        _ kind: NotificationKind,
        anchor: Date,
        action: NotificationPlanningSettings.Action,
        event: MBEvent,
        now: Date,
        into planned: inout [PlannedNotification]
    ) {
        guard action.enabled else { return }
        let fireDate = anchor.addingTimeInterval(-action.offset)
        guard fireDate > now else { return }
        planned.append(PlannedNotification(
            eventID: event.id,
            kind: kind,
            fireDate: fireDate,
            identity: identity(eventID: event.id, lastModified: event.lastModifiedDate, kind: kind, offset: action.offset)
        ))
    }

    private static func identity(
        eventID: String,
        lastModified: Date?,
        kind: NotificationKind,
        offset: TimeInterval
    ) -> String {
        let modifiedKey = lastModified.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        return "\(eventID)|\(modifiedKey)|\(kind.rawValue)|\(Int(offset))"
    }
}
