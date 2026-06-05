//
//  Notifications.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import AppKit
import UserNotifications

func sendUserNotification(_ title: String, _ text: String) async {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = text

    let identifier = UUID().uuidString

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

    let center = UNUserNotificationCenter.current()
    do {
        try await center.add(request)
    } catch {
        let errorDescription = String(describing: error)
        MeetingBarLogger.notifications.error(
            "Could not add request \(request.identifier, privacy: .private): \(errorDescription, privacy: .private)"
        )
    }
}

/// check whether the notifications for meetingbar are enabled and alert or banner style is enabled.
/// in this case the method will return true, otherwise false.
func notificationsEnabled() async -> Bool {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    let styleOK = settings.alertStyle == .alert || settings.alertStyle == .banner
    return styleOK && settings.authorizationStatus != .denied
}

/// sends a notification to the user.
func sendNotification(_ title: String, _ text: String) {
    Task {
        if await notificationsEnabled() {
            await sendUserNotification(title, text)
        } else {
            await MainActor.run {
                displayAlert(title: title, text: text)
            }
        }
    }
}

/// adds an alert for the user- we will only use NSAlert if the user has switched off notifications
@MainActor
func displayAlert(title: String, text: String) {
    let userAlert = NSAlert()
    userAlert.messageText = title
    userAlert.informativeText = text
    userAlert.alertStyle = NSAlert.Style.informational
    userAlert.addButton(withTitle: "general_ok".loco())

    userAlert.runModal()
}

func removeDeliveredNotifications() {
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
}
