//
//  Notifications.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit
import UserNotifications

import Defaults

func requestNotificationAuthorization() {
    let center = UNUserNotificationCenter.current()

    center.getNotificationSettings { notificationSettings in
        NSLog("Before Alert settings \(notificationSettings.alertSetting.rawValue)")
        NSLog("Before Alert Style settings \(notificationSettings.alertStyle.rawValue)")
        NSLog("Before Authorisation status \(notificationSettings.authorizationStatus.rawValue)")
    }

    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
        if granted {
            NSLog("Access to notications granted")
        } else {
            NSLog("Access to notications denied")
        }
    }

    center.getNotificationSettings { notificationSettings in
        NSLog("After Alert settings \(notificationSettings.alertSetting.rawValue)")
        NSLog("After Alert Style settings \(notificationSettings.alertStyle.rawValue)")
        NSLog("After Authorisation status \(notificationSettings.authorizationStatus.rawValue)")
    }
}

func registerNotificationCategories() {
    DispatchQueue.main.async {
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

        notificationCenter.getNotificationCategories { categories in
            for category in categories {
                NSLog("Before Category \(category.identifier) registered")
            }
        }

        notificationCenter.setNotificationCategories([eventCategory])

        notificationCenter.getNotificationCategories { categories in
            for category in categories {
                NSLog("After Category \(category.identifier) registered")
            }
        }
    }
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
    center.add(request) { error in
        if let error = error {
            NSLog("%@", "request \(request) could not be added because of error \(error)")
        } else {
            NSLog("%@", "request \(request) was added")
        }
    }}

func scheduleEventNotification(_ event: EKEvent) {
    requestNotificationAuthorization() // By the apple best practices

    let now = Date()
    let notificationTime = Double(Defaults[.joinEventNotificationTime].rawValue)
    let timeInterval = event.startDate.timeIntervalSince(now) - notificationTime

    if timeInterval < 0.5 {
        return
    }

    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = event.title
    content.body = "The event starts soon"
    content.categoryIdentifier = "EVENT"
    content.sound = UNNotificationSound.default
    content.userInfo = ["eventID": event.eventIdentifier!]
    content.threadIdentifier = "meetingbar"

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(identifier: "NEXT_EVENT", content: content, trigger: trigger)
    center.add(request) { error in
        if let error = error {
            NSLog("%@", "request \(request) could not be added because of error \(error)")
        } else {
            NSLog("%@", "request \(request) was added")
        }
    }
}

func scheduleTestEventNotification() {
    requestNotificationAuthorization() // By the apple best practices

    let timeInterval = 0.1

    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = "Test title"
    content.body = "The event starts soon"
    content.subtitle = "Test subtitle"
    content.categoryIdentifier = "EVENT"
    content.sound = UNNotificationSound.default
    content.userInfo = ["eventID": "1"]
    content.badge = 1
   // content.threadIdentifier = "meetingbar"

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    center.add(request) { error in
        if let error = error {
            NSLog("%@", "request \(request) could not be added because of error \(error)")
        } else {
            NSLog("%@", "request \(request) was added")
        }
    }
}
