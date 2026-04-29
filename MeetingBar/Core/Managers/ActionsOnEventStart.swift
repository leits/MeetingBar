//
//  ActionsOnEventStart.swift
//  MeetingBar
//
//  Created by Jens Goldhammer  on 22.03.22.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import Defaults
import Foundation

@MainActor
class ActionsOnEventStart: NSObject {
    var app: AppDelegate
    var timer: Timer?

    init(_ appDelegate: AppDelegate) {
        app = appDelegate
    }

    func startWatching() {
        timer = Timer(timeInterval: 10, target: self, selector: #selector(checkNextEvent), userInfo: nil, repeats: true)
        timer?.tolerance = 0.5
        RunLoop.current.add(timer!, forMode: .common)
    }

    /// Decides whether to fire the configured per-event actions for the
    /// currently selected next event:
    ///
    /// - fullscreen notification (if enabled),
    /// - auto-join meeting (if enabled),
    /// - on-event-start AppleScript (if enabled).
    ///
    /// All-day events fire actions for the duration of the event. Each action
    /// keeps its own processed-events list in `Defaults` so back-to-back
    /// invocations of this method only fire once per (event id, lastModifiedDate)
    /// pair.
    @objc
    private func checkNextEvent() {
        if app.screenIsLocked { return }
        let now = Date()

        Defaults[.processedEventsForFullscreenNotification] =
            cleanupExpiredActionRecords(Defaults[.processedEventsForFullscreenNotification], now: now)
        Defaults[.processedEventsForAutoJoin] =
            cleanupExpiredActionRecords(Defaults[.processedEventsForAutoJoin], now: now)
        Defaults[.processedEventsForRunScriptOnEventStart] =
            cleanupExpiredActionRecords(Defaults[.processedEventsForRunScriptOnEventStart], now: now)

        let fullscreenActive = Defaults[.fullscreenNotification]
        let autoJoinActive = Defaults[.automaticEventJoin]
        let scriptActive = Defaults[.runEventStartScript] && Defaults[.eventStartScriptLocation] != nil

        guard fullscreenActive || autoJoinActive || scriptActive else { return }
        guard let nextEvent = app.statusBarItem.events.nextEvent(linkRequired: true) else { return }

        if fullscreenActive {
            processFullscreenNotification(event: nextEvent, now: now)
        }
        if autoJoinActive {
            processAutoJoin(event: nextEvent, now: now)
        }
        if scriptActive {
            processStartScript(event: nextEvent, now: now)
        }
    }

    private func processFullscreenNotification(event: MBEvent, now: Date) {
        let config = EventActionConfig(
            actionTime: Double(Defaults[.fullscreenNotificationTime].rawValue),
            allowsRecentlyStarted: true,
            requiresMeetingLink: true
        )
        guard let decision = EventActionPolicy.evaluate(
            event: EventActionEvent(event: event),
            config: config,
            processed: Defaults[.processedEventsForFullscreenNotification].actionRecords,
            now: now
        ) else { return }

        if decision.shouldFireSideEffect {
            app.openFullscreenNotificationWindow(event: event)
        }
        Defaults[.processedEventsForFullscreenNotification] = decision.updatedProcessed.processedEvents
    }

    private func processAutoJoin(event: MBEvent, now: Date) {
        let config = EventActionConfig(
            actionTime: Double(Defaults[.automaticEventJoinTime].rawValue),
            allowsRecentlyStarted: true,
            requiresMeetingLink: true
        )
        guard let decision = EventActionPolicy.evaluate(
            event: EventActionEvent(event: event),
            config: config,
            processed: Defaults[.processedEventsForAutoJoin].actionRecords,
            now: now
        ) else { return }

        if decision.shouldFireSideEffect {
            event.openMeeting()
        }
        Defaults[.processedEventsForAutoJoin] = decision.updatedProcessed.processedEvents
    }

    private func processStartScript(event: MBEvent, now: Date) {
        let config = EventActionConfig(
            actionTime: Double(Defaults[.eventStartScriptTime].rawValue),
            allowsRecentlyStarted: false,
            requiresMeetingLink: false
        )
        guard let decision = EventActionPolicy.evaluate(
            event: EventActionEvent(event: event),
            config: config,
            processed: Defaults[.processedEventsForRunScriptOnEventStart].actionRecords,
            now: now
        ) else { return }

        if decision.shouldFireSideEffect {
            runMeetingStartsScript(event: event, type: ScriptType.meetingStart)
        }
        Defaults[.processedEventsForRunScriptOnEventStart] = decision.updatedProcessed.processedEvents
    }
}

private func cleanupExpiredActionRecords(_ processed: [ProcessedEvent], now: Date) -> [ProcessedEvent] {
    EventActionPolicy
        .cleanupExpired(processed.actionRecords, now: now)
        .processedEvents
}

private extension EventActionEvent {
    init(event: MBEvent) {
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

private extension EventActionProcessedEvent {
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

private extension Array where Element == ProcessedEvent {
    var actionRecords: [EventActionProcessedEvent] {
        map(EventActionProcessedEvent.init(processedEvent:))
    }
}

private extension Array where Element == EventActionProcessedEvent {
    var processedEvents: [ProcessedEvent] {
        map(\.processedEvent)
    }
}
