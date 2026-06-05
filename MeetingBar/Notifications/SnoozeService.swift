//
//  SnoozeService.swift
//  MeetingBar
//

import Foundation
import UserNotifications

struct SnoozePlan: Equatable {
    let triggerInterval: TimeInterval

    static func make(
        eventStartDate: Date,
        action: NotificationEventTimeAction,
        now: Date
    ) -> SnoozePlan {
        let interval: TimeInterval
        if action == .untilStart {
            interval = eventStartDate.timeIntervalSince(now)
        } else {
            interval = TimeInterval(action.durationInSeconds)
        }

        // UserNotifications rejects non-positive time interval triggers.
        return SnoozePlan(triggerInterval: max(interval, 0.5))
    }
}

enum SnoozeNotificationRequestFactory {
    static func request(
        event: MBEvent,
        interval: NotificationEventTimeAction,
        hideMeetingTitle: Bool,
        now: Date
    ) -> UNNotificationRequest {
        let plan = SnoozePlan.make(
            eventStartDate: event.startDate,
            action: interval,
            now: now
        )
        let content = UNMutableNotificationContent()

        content.title = hideMeetingTitle ? "general_meeting".loco() : event.title
        content.categoryIdentifier = EventNotificationIdentifiers.snoozeCategory
        content.sound = UNNotificationSound.default
        content.userInfo = ["eventID": event.id]
        content.threadIdentifier = "meetingbar"
        content.body = "notifications_event_started_body".loco()
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: plan.triggerInterval,
            repeats: false
        )
        return UNNotificationRequest(
            identifier: notificationIDs.event_starts,
            content: content,
            trigger: trigger
        )
    }
}

/// Owns replacement of the pending event-start notification with a snoozed request.
@MainActor
final class SnoozeService {
    private let sink: NotificationRequestSink
    private let clock: AppClock
    private let hideMeetingTitle: () -> Bool

    init(
        sink: NotificationRequestSink = UNUserNotificationCenter.current(),
        clock: AppClock = .live,
        hideMeetingTitle: @escaping () -> Bool = {
            AppSettings.current.statusBar.hideMeetingTitle
        }
    ) {
        self.sink = sink
        self.clock = clock
        self.hideMeetingTitle = hideMeetingTitle
    }

    func snooze(
        event: MBEvent,
        action: NotificationEventTimeAction
    ) async {
        sink.removePending(identifiers: [notificationIDs.event_starts])

        let request = SnoozeNotificationRequestFactory.request(
            event: event,
            interval: action,
            hideMeetingTitle: hideMeetingTitle(),
            now: clock.now()
        )
        do {
            try await sink.add(request)
        } catch {
            NSLog(
                "%@",
                "request \(request.identifier) could not be added because of error \(error)"
            )
        }
    }
}
