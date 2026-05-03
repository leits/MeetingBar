//
//  NotificationRecordStore.swift
//  MeetingBar
//

import Defaults
import Foundation

/// Owns read/write access to the persisted processed-event records that track
/// which in-app notification actions have already fired.
///
/// Centralising these Defaults reads and writes makes the scheduler testable
/// without touching `UserDefaults` and isolates the persistence format from the
/// scheduling logic.
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
