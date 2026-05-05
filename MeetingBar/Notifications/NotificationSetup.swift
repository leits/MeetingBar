//
//  NotificationSetup.swift
//  MeetingBar
//

import Defaults
import UserNotifications

// MARK: - Authorization

@MainActor private var didRequestAuth = false

@MainActor func ensureNotificationAuthorization() async {
    guard !didRequestAuth else { return }  // ask once
    didRequestAuth = true
    do {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert, .badge, .sound
        ])
    } catch {}
}

// MARK: - Categories

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

// MARK: - Snooze

enum SnoozeNotificationRequestFactory {
    static func request(
        event: MBEvent,
        interval: NotificationEventTimeAction,
        hideMeetingTitle: Bool,
        now: Date
    ) -> UNNotificationRequest {
        var timeInterval = Double(interval.durationInSeconds)
        let content = UNMutableNotificationContent()

        if hideMeetingTitle {
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
        return UNNotificationRequest(
            identifier: notificationIDs.event_starts,
            content: content,
            trigger: trigger
        )
    }
}

@MainActor
func snoozeEventNotification(_ event: MBEvent, _ interval: NotificationEventTimeAction) async {
    removePendingNotificationRequests(withID: notificationIDs.event_starts)

    let request = SnoozeNotificationRequestFactory.request(
        event: event,
        interval: interval,
        hideMeetingTitle: Defaults[.hideMeetingTitle],
        now: Date()
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
