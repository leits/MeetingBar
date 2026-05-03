//
//  NotificationContentFactory.swift
//  MeetingBar
//

import Foundation
import UserNotifications

/// Builds `UNNotificationRequest` objects from a planned notification.
///
/// All content construction — titles, bodies, category identifiers, triggers —
/// lives here so `NotificationScheduler` is responsible only for reconciliation.
enum NotificationContentFactory {
    static func request(
        for plan: PlannedNotification,
        event: MBEvent,
        settings: NotificationPlanningSettings,
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
            content.body = ""
        }

        // Floor at 0.5s so the OS does not reject a too-immediate trigger.
        let interval = max(plan.fireDate.timeIntervalSince(now), 0.5)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(
            identifier: NotificationScheduler.identifierPrefix + plan.identity,
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
