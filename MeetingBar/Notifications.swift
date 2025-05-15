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

@MainActor private var didRequestAuth = false

// Termporary workaround to not schedule notification for the same event on every update
private struct EventFP: Equatable {
    let id: String
    let start: Date
    let end: Date
}

@MainActor private var lastScheduleEventFP: EventFP?

@MainActor func ensureNotificationAuthorization() async {
    guard !didRequestAuth else { return } // ask once
    didRequestAuth = true
    do {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    } catch {}
}

@MainActor func registerNotificationCategories() {
    let acceptAction = UNNotificationAction(
        identifier: "JOIN_ACTION",
        title: "notifications_meetingbar_join_event_action".loco(),
        options: .foreground
    )

    let dismissAction = UNNotificationAction(
        identifier: "DISMISS_ACTION",
        title: "notifications_meetingbar_dismiss_event_action".loco(),
        options: .foreground
    )

    let snoozeUntilStartTime = UNNotificationAction(
        identifier: NotificationEventTimeAction.untilStart.rawValue,
        title: "notifications_snooze_until_start".loco(),
        options: .foreground
    )

    let snooze5Min = UNNotificationAction(
        identifier: NotificationEventTimeAction.fiveMinuteLater.rawValue,
        title: "notifications_snooze_for".loco(
            String(NotificationEventTimeAction.fiveMinuteLater.durationInMins)),
        options: .foreground
    )

    let snooze10Min = UNNotificationAction(
        identifier: NotificationEventTimeAction.tenMinuteLater.rawValue,
        title: "notifications_snooze_for".loco(
            String(NotificationEventTimeAction.tenMinuteLater.durationInMins)),
        options: .foreground
    )

    let snooze15Min = UNNotificationAction(
        identifier: NotificationEventTimeAction.fifteenMinuteLater.rawValue,
        title: "notifications_snooze_for".loco(
            String(NotificationEventTimeAction.fifteenMinuteLater.durationInMins)),
        options: .foreground
    )

    let snooze30Min = UNNotificationAction(
        identifier: NotificationEventTimeAction.thirtyMinuteLater.rawValue,
        title: "notifications_snooze_for".loco(
            String(NotificationEventTimeAction.thirtyMinuteLater.durationInMins)),
        options: .foreground
    )

    let eventCategory = UNNotificationCategory(
        identifier: "EVENT",
        actions: [
            acceptAction, dismissAction, snoozeUntilStartTime, snooze5Min, snooze10Min, snooze15Min,
            snooze30Min
        ],
        intentIdentifiers: [],
        hiddenPreviewsBodyPlaceholder: "",
        options: [.customDismissAction, .hiddenPreviewsShowTitle]
    )

    let snoozeEventCategory = UNNotificationCategory(
        identifier: "SNOOZE_EVENT",
        actions: [acceptAction, dismissAction, snooze5Min, snooze10Min, snooze15Min, snooze30Min],
        intentIdentifiers: [],
        hiddenPreviewsBodyPlaceholder: "",
        options: [.customDismissAction, .hiddenPreviewsShowTitle]
    )

    let center = UNUserNotificationCenter.current()
    center.setNotificationCategories([eventCategory, snoozeEventCategory])
}

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
        NSLog(
            "%@",
            "request \(request.identifier) could not be added because of error \(error)"
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

@MainActor func scheduleEventNotification(_ event: MBEvent) async {
    if !Defaults[.joinEventNotification], !Defaults[.endOfEventNotification] {
        return
    }

    let fp = EventFP(id: event.id, start: event.startDate, end: event.endDate)
    guard fp != lastScheduleEventFP else { return } // ← skip already scheduled if no changes
    lastScheduleEventFP = fp

    let now = Date()

    // Event start notification
    if Defaults[.joinEventNotification] {
        let notificationTime = Double(Defaults[.joinEventNotificationTime].rawValue)
        let timeInterval = event.startDate.timeIntervalSince(now) - notificationTime

        if timeInterval < 0.5 {
            return
        }

        removePendingNotificationRequests(withID: notificationIDs.event_starts)

        let content = UNMutableNotificationContent()
        if Defaults[.hideMeetingTitle] {
            content.title = "general_meeting".loco()
        } else {
            content.title = event.title
        }
        content.interruptionLevel = .timeSensitive

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
        content.userInfo = ["eventID": event.id]
        content.threadIdentifier = "meetingbar"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIDs.event_starts, content: content, trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(request)
        } catch {
            NSLog(
                "%@",
                "request \(request.identifier) could not be added because of error \(error)"
            )
        }
    }

    // Event end notification
    if Defaults[.endOfEventNotification] {
        let notificationTime = Double(Defaults[.endOfEventNotificationTime].rawValue)
        let timeInterval = event.endDate.timeIntervalSince(now) - notificationTime

        if timeInterval < 0.5 {
            return
        }

        let content = UNMutableNotificationContent()
        if Defaults[.hideMeetingTitle] {
            content.title = "general_meeting".loco()
        } else {
            content.title = event.title
        }
        content.interruptionLevel = .timeSensitive

        switch Defaults[.endOfEventNotificationTime] {
        case .atEnd:
            content.body = "notifications_event_ends_soon_body".loco()
        case .minuteBefore:
            content.body = "notifications_event_ends_one_minute_body".loco()
        case .threeMinuteBefore:
            content.body = "notifications_event_ends_three_minutes_body".loco()
        case .fiveMinuteBefore:
            content.body = "notifications_event_ends_five_minutes_body".loco()
        }
        //        content.categoryIdentifier = "EVENT"
        content.sound = UNNotificationSound.default
        content.userInfo = ["eventID": event.id]
        content.threadIdentifier = "meetingbar"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIDs.event_ends, content: content, trigger: trigger
        )
        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(request)
        } catch {
            NSLog(
                "%@",
                "request \(request.identifier) could not be added because of error \(error)"
            )
        }
    }
}

@MainActor
func snoozeEventNotification(_ event: MBEvent, _ interval: NotificationEventTimeAction) async {
    removePendingNotificationRequests(withID: notificationIDs.event_starts)

    let now = Date()
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
    content.userInfo = ["eventID": event.id]
    content.threadIdentifier = "meetingbar"
    content.body = "notifications_event_started_body".loco()
    content.interruptionLevel = .timeSensitive

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(
        identifier: notificationIDs.event_starts, content: content, trigger: trigger
    )
    let center = UNUserNotificationCenter.current()
    do {
        try await center.add(request)
    } catch {
        NSLog(
            "%@",
            "request \(request.identifier) could not be added because of error \(error)"
        )
    }
}

func removePendingNotificationRequests(withID: String) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [withID])
    //    center.removeAllPendingNotificationRequests()
}

func removeDeliveredNotifications() {
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
}
