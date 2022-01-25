//
//  Notifications.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import AppKit
import Defaults
import EventKit
import UserNotifications

func requestNotificationAuthorization() {
    let center = UNUserNotificationCenter.current()

    center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
}

func registerNotificationCategories() {
    let acceptAction = UNNotificationAction(identifier: "JOIN_ACTION",
                                            title: "Join",
                                            options: .foreground)

    let eventCategory =
        UNNotificationCategory(identifier: "EVENT",
                               actions: [acceptAction],
                               intentIdentifiers: [],
                               hiddenPreviewsBodyPlaceholder: "",
                               options: [.customDismissAction, .hiddenPreviewsShowTitle])

    let notificationCenter = UNUserNotificationCenter.current()

    notificationCenter.setNotificationCategories([eventCategory])

    notificationCenter.getNotificationCategories { categories in
        for category in categories {
            NSLog("Category \(category.identifier) was registered")
        }
    }
}

func sendUserNotification(_ title: String, _ text: String) {
    requestNotificationAuthorization() // By the apple best practices

    NSLog("Send notification: \(title) - \(text)")
    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = text

    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

    center.add(request) { error in
        if let error = error {
            NSLog("%@", "request \(request.identifier) could not be added because of error \(error)")
        }
    }
}

/**
 * check whether the notifications for meetingbar are enabled and alert or banner style is enabled.
 * in this case the method will return true, otherwise false.
 *
 */
func notificationsEnabled() -> Bool {
    let center = UNUserNotificationCenter.current()
    let group = DispatchGroup()
    group.enter()

    var correctAlertStyle = false
    var notificationsEnabled = false

    center.getNotificationSettings { notificationSettings in
        correctAlertStyle = notificationSettings.alertStyle == UNAlertStyle.alert || notificationSettings.alertStyle == UNAlertStyle.banner
        notificationsEnabled = notificationSettings.authorizationStatus != UNAuthorizationStatus.denied
        group.leave()
    }

    group.wait()
    return correctAlertStyle && notificationsEnabled
}

/**
 * sends a notification to the user.
 */
func sendNotification(_ title: String, _ text: String) {
    requestNotificationAuthorization() // By the apple best practices

    if notificationsEnabled() {
        sendUserNotification(title, text)
    } else {
        displayAlert(title: title, text: text)
    }
}

/**
 * adds an alert for the user- we will only use NSAlert if the user has switched off notifications
 */
func displayAlert(title: String, text: String) {
    NSLog("Display alert: \(title) - \(text)")

    let userAlert = NSAlert()
    userAlert.messageText = title
    userAlert.informativeText = text
    userAlert.alertStyle = NSAlert.Style.informational
    userAlert.addButton(withTitle: "general_ok".loco())

    userAlert.runModal()
}

func scheduleEventNotification(_ event: EKEvent) {
    requestNotificationAuthorization() // By the apple best practices

    let now = Date()
    let notificationTime = Double(Defaults[.joinEventNotificationTime].rawValue)
    let timeInterval = event.startDate.timeIntervalSince(now) - notificationTime

    if timeInterval < 0.5 {
        return
    }

    removePendingNotificationRequests()

    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    if Defaults[.hideMeetingTitle] {
        content.title = "general_meeting".loco()
    } else {
        content.title = event.title
    }

    switch Defaults[.joinEventNotificationTime] {
    case .atStart:
        content.body = "notifications_event_start_soon_body".loco()
    case .minuteBefore:
        content.body = "notifications_event_start_one_minute_body".loco()
    case .threeMinuteBefore:
        content.body = "notifications_event_start_three_minutes_body".loco()
    case .fiveMinuteBefore:
        content.body = "notifications_event_start_five_minutes_body".loco()
    }
    content.categoryIdentifier = "EVENT"
    content.sound = UNNotificationSound.default
    content.userInfo = ["eventID": event.eventIdentifier!]
    content.threadIdentifier = "meetingbar"

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(identifier: "NEXT_EVENT", content: content, trigger: trigger)
    center.add(request) { error in
        if let error = error {
            NSLog("%@", "request \(request.identifier) could not be added because of error \(error)")
        }
    }
}

func removePendingNotificationRequests() {
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
}

func removeDeliveredNotifications() {
    let center = UNUserNotificationCenter.current()
    center.removeAllDeliveredNotifications()
}
