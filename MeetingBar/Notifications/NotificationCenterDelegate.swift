//
//  NotificationCenterDelegate.swift
//  MeetingBar
//

import UserNotifications

/// Handles `UNUserNotificationCenter` delegate callbacks and translates them
/// into app-level response actions.
///
/// This class owns the UN delegate role so `AppDelegate` only needs to wire it
/// up and does not implement `UNUserNotificationCenterDelegate` itself.
@MainActor
final class NotificationCenterDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let actionHandler: (NotificationResponseAction) -> Void

    init(actionHandler: @escaping (NotificationResponseAction) -> Void) {
        self.actionHandler = actionHandler
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

        let content = response.notification.request.content
        guard let action = NotificationResponseAction(
            categoryIdentifier: content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier,
            eventID: content.userInfo["eventID"] as? String,
            defaultActionIdentifier: UNNotificationDefaultActionIdentifier
        ) else {
            return
        }

        actionHandler(action)
    }
}
