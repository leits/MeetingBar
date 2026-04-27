//
//  EventActionPolicy.swift
//  MeetingBar
//

import Foundation

/// Configures the time window and link requirement for a per-event action
/// (fullscreen notification, auto-join, on-start script).
struct EventActionConfig {
    /// Upper bound of the firing window in seconds before `event.startDate`.
    /// Read from the user-configured Defaults key for the action.
    let actionTime: TimeInterval

    /// `true` if the action may still fire in the first 15 seconds after the
    /// event has started (fullscreen, auto-join). `false` if the action only
    /// runs strictly before the event starts (on-start script).
    let allowsRecentlyStarted: Bool

    /// `true` if the side-effect should be skipped when the event has no
    /// meeting link, while still updating the processed-events list to
    /// dedup retries. Used by fullscreen and auto-join.
    let requiresMeetingLink: Bool
}

enum EventActionPolicy {
    struct Decision: Equatable {
        let updatedProcessed: [ProcessedEvent]
        let shouldFireSideEffect: Bool
    }

    /// Returns `nil` when no Defaults change is needed: either the event is
    /// outside the action window, or it has already been processed at the
    /// current `lastModifiedDate`.
    static func evaluate(
        event: MBEvent,
        config: EventActionConfig,
        processed: [ProcessedEvent],
        now: Date
    ) -> Decision? {
        let timeInterval = event.startDate.timeIntervalSince(now)
        let lowerBound = config.allowsRecentlyStarted ? -15.0 : 0.0
        let withinWindow = timeInterval > lowerBound && timeInterval < config.actionTime
        let allDayActive = event.isAllDay && (event.startDate ... event.endDate).contains(now)
        guard withinWindow || allDayActive else { return nil }

        let matched = processed.first { $0.id == event.id }
        if let matched, matched.lastModifiedDate == event.lastModifiedDate {
            return nil
        }

        var updated = processed
        if matched != nil {
            updated.removeAll { $0.id == event.id }
        }
        updated.append(ProcessedEvent(
            id: event.id,
            lastModifiedDate: event.lastModifiedDate,
            eventEndDate: event.endDate
        ))

        let shouldFire = !config.requiresMeetingLink || event.meetingLink != nil
        return Decision(updatedProcessed: updated, shouldFireSideEffect: shouldFire)
    }

    /// Drops processed-event entries whose underlying event has already ended.
    static func cleanupExpired(_ processed: [ProcessedEvent], now: Date) -> [ProcessedEvent] {
        processed.filter { $0.eventEndDate.timeIntervalSince(now) > 0 }
    }
}
