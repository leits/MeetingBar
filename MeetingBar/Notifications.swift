//
//  Notifications.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit
import UserNotifications

func requestNotificationAuthorization() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
        if granted {
            NSLog("Access to notications granted")
        } else {
            NSLog("Access to notications denied")
        }
    }
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
                               options: .customDismissAction)

    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.setNotificationCategories([eventCategory])
}

func sendNotification(_ title: String, _ text: String) {
    requestNotificationAuthorization() // By the apple best practices

    NSLog("Send notification: \(title) - \(text)")
    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = text

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    center.add(request)
}

func scheduleEventNotification(_ event: EKEvent, _ text: String) {
    requestNotificationAuthorization() // By the apple best practices

    NSLog("Send join notification: \(String(describing: event.title)) - \(text)")
    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = event.title
    content.body = text
    content.categoryIdentifier = "EVENT"
    content.sound = UNNotificationSound.default
    content.userInfo = ["eventID": event.eventIdentifier!]

    let now = Date()
    var timeInterval = event.startDate.timeIntervalSince(now) - 5 // send notification 5 second before event
    timeInterval = timeInterval > 0.1 ? timeInterval : 0.1
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(identifier: "next_event", content: content, trigger: trigger)
    center.add(request)
}
