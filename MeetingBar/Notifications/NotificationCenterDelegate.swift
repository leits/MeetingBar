//
//  NotificationCenterDelegate.swift
//  MeetingBar
//

import UserNotifications

/// Handles `UNUserNotificationCenter` delegate callbacks and translates them
/// into higher-level actions (open meeting, dismiss, snooze).
///
/// This class owns the UN delegate role so `AppDelegate` only needs to wire it
/// up and does not implement `UNUserNotificationCenterDelegate` itself.
@MainActor
final class NotificationCenterDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    /// Closure that resolves an event by ID from the current status bar events.
    var eventProvider: (String) -> MBEvent?

    /// Closure that dismisses an event.
    var dismissHandler: (MBEvent) -> Void

    init(
        eventProvider: @escaping (String) -> MBEvent?,
        dismissHandler: @escaping (MBEvent) -> Void
    ) {
        self.eventProvider = eventProvider
        self.dismissHandler = dismissHandler
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows notifications even when the app has focus.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list, .banner, .badge, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard
            ["EVENT", "SNOOZE_EVENT"].contains(
                response.notification.request.content.categoryIdentifier),
            let eventID = response.notification.request.content.userInfo["eventID"] as? String,
            let event = eventProvider(eventID)
        else {
            return
        }

        Task {
            switch response.actionIdentifier {
            case "JOIN_ACTION", UNNotificationDefaultActionIdentifier:
                event.openMeeting()
            case "DISMISS_ACTION":
                dismissHandler(event)
            case NotificationEventTimeAction.untilStart.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.untilStart)
            case NotificationEventTimeAction.fiveMinuteLater.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.fiveMinuteLater)
            case NotificationEventTimeAction.tenMinuteLater.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.tenMinuteLater)
            case NotificationEventTimeAction.fifteenMinuteLater.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.fifteenMinuteLater)
            case NotificationEventTimeAction.thirtyMinuteLater.rawValue:
                await snoozeEventNotification(event, NotificationEventTimeAction.thirtyMinuteLater)
            default:
                break
            }
        }
    }
}
