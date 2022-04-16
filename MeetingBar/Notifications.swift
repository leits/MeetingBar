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

    let snoozeUntilStartTime = UNNotificationAction(identifier: NotificationEventTimeAction.untilStart.rawValue,
                                                    title: "Snooze until start time",
                                                    options: .foreground)

    let snooze5Min = UNNotificationAction(identifier: NotificationEventTimeAction.fiveMinuteLater.rawValue,
                                          title: "Snooze for \(NotificationEventTimeAction.fiveMinuteLater.durationInMins) min",
                                          options: .foreground)

    let snooze10Min = UNNotificationAction(identifier: NotificationEventTimeAction.tenMinuteLater.rawValue,
                                           title: "Snooze for \(NotificationEventTimeAction.tenMinuteLater.durationInMins) min",
                                           options: .foreground)

    let snooze15Min = UNNotificationAction(identifier: NotificationEventTimeAction.fifteenMinuteLater.rawValue,
                                           title: "Snooze for \(NotificationEventTimeAction.fifteenMinuteLater.durationInMins) min",
                                           options: .foreground)

    let snooze30Min = UNNotificationAction(identifier: NotificationEventTimeAction.thirtyMinuteLater.rawValue,
                                           title: "Snooze for \(NotificationEventTimeAction.thirtyMinuteLater.durationInMins) min",
                                           options: .foreground)

    let eventCategory = UNNotificationCategory(identifier: "EVENT",
                                               actions: [acceptAction, snoozeUntilStartTime, snooze5Min, snooze10Min, snooze15Min, snooze30Min],
                                               intentIdentifiers: [],
                                               hiddenPreviewsBodyPlaceholder: "",
                                               options: [.customDismissAction, .hiddenPreviewsShowTitle])

    let snoozeEventCategory = UNNotificationCategory(identifier: "SNOOZE_EVENT",
                                                     actions: [acceptAction, snooze5Min, snooze10Min, snooze15Min, snooze30Min],
                                                     intentIdentifiers: [],
                                                     hiddenPreviewsBodyPlaceholder: "",
                                                     options: [.customDismissAction, .hiddenPreviewsShowTitle])

    let notificationCenter = UNUserNotificationCenter.current()

    notificationCenter.setNotificationCategories([eventCategory, snoozeEventCategory])

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
    
    if Defaults[.joinEventNotification] {
        scheduleEventStartNotification(event);
    }
    
    if Defaults[.eventEndsNotification] {
        scheduleEventEndNotification(event);
    }
    
}

/**
 * schedules the notification for the start of the next meeting.
 * It allows to open the meeting
 */
func scheduleEventStartNotification(_ event: EKEvent) {
    requestNotificationAuthorization() // By the apple best practices

    let now = Date()
    let notificationTime = Double(Defaults[.joinEventNotificationTime].rawValue)
    let timeInterval = event.startDate.timeIntervalSince(now) - notificationTime

    if timeInterval < 0.5 {
        return
    }

    removePendingNotificationRequests("NEXT_EVENT")

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

/**
 * schedules the notification for the next event end.
 */
func scheduleEventEndNotification(_ event: EKEvent) {
    requestNotificationAuthorization() // By the apple best practices

    let now = Date()
    let notificationTime = Double(Defaults[.eventEndsNotificationTime].rawValue)
    let timeInterval = event.endDate.timeIntervalSince(now) - notificationTime

    if timeInterval < 0.5 {
        return
    }

    removePendingNotificationRequests("EVENT_ENDS")

    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    if Defaults[.hideMeetingTitle] {
        content.title = "general_meeting".loco()
    } else {
        content.title = event.title
    }

    switch Defaults[.eventEndsNotificationTime] {
    case .atEnd:
        content.body = "notifications_event_ends_soon_body".loco()
    case .minuteBefore:
        content.body = "notifications_event_ends_one_minute_body".loco()
    case .twoMinutesBefore:
        content.body = "notifications_event_ends_three_minutes_body".loco()
    case .threeMinutesBefore:
        content.body = "notifications_event_ends_three_minutes_body".loco()
    case .fiveMinutesBefore:
        content.body = "notifications_event_ends_five_minutes_body".loco()
    case .tenMinutesBefore:
        content.body = "notifications_event_ends_five_minutes_body".loco()
    }
    
    content.categoryIdentifier = "EVENT"
    content.sound = UNNotificationSound.default
    content.userInfo = ["eventID": event.eventIdentifier!]
    content.threadIdentifier = "meetingbar"

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(identifier: "EVENT_ENDS", content: content, trigger: trigger)
    center.add(request) { error in
        if let error = error {
            NSLog("%@", "request \(request.identifier) could not be added because of error \(error)")
        }
    }
}

func snoozeEventNotification(_ event: EKEvent, _ interval: NotificationEventTimeAction) {
    requestNotificationAuthorization() // By the apple best practices
    removePendingNotificationRequests()

    let now = Date()
    let center = UNUserNotificationCenter.current()
    var timeInterval = Double(interval.durationInSeconds)
    let content = UNMutableNotificationContent()

    if Defaults[.hideMeetingTitle] {
        content.title = "general_meeting".loco()
    } else {
        content.title = event.title
    }

    if interval == .untilStart {
        timeInterval = event.startDate.timeIntervalSince(now)
    }

    content.categoryIdentifier = "SNOOZE_EVENT"
    content.sound = UNNotificationSound.default
    content.userInfo = ["eventID": event.eventIdentifier!]
    content.threadIdentifier = "meetingbar"
    content.body = "notifications_event_started_body".loco()

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

func removePendingNotificationRequests(identifier:String?) {
    let center = UNUserNotificationCenter.current()
    if identifier != nil {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    } else {
        center.removeAllPendingNotificationRequests()
    }
}

func removeDeliveredNotifications() {
    let center = UNUserNotificationCenter.current()
    center.removeAllDeliveredNotifications()
}
