//
//  NotificationSetup.swift
//  MeetingBar
//

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
        identifier: EventNotificationIdentifiers.joinAction,
        title: "notifications_meetingbar_join_event_action".loco(),
        options: .foreground
    )

    let dismissAction = UNNotificationAction(
        identifier: EventNotificationIdentifiers.dismissAction,
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
        identifier: EventNotificationIdentifiers.eventCategory,
        actions: [
            acceptAction, dismissAction, snoozeUntilStartTime, snooze5Min, snooze10Min, snooze15Min,
            snooze30Min
        ],
        intentIdentifiers: [],
        hiddenPreviewsBodyPlaceholder: "",
        options: [.customDismissAction, .hiddenPreviewsShowTitle]
    )

    let snoozeEventCategory = UNNotificationCategory(
        identifier: EventNotificationIdentifiers.snoozeCategory,
        actions: [acceptAction, dismissAction, snooze5Min, snooze10Min, snooze15Min, snooze30Min],
        intentIdentifiers: [],
        hiddenPreviewsBodyPlaceholder: "",
        options: [.customDismissAction, .hiddenPreviewsShowTitle]
    )

    let center = UNUserNotificationCenter.current()
    center.setNotificationCategories([eventCategory, snoozeEventCategory])
}
