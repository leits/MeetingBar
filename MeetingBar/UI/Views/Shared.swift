//
//  Shared.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import Foundation
import LaunchAtLogin
import SwiftUI
import UserNotifications

/**
 * users can decide to automatically open events in the configured application
 */
struct AutomaticEventJoinPicker: View {
    @Default(.automaticEventJoin) var automaticEventJoin
    @Default(.automaticEventJoinTime) var automaticEventJoinTime

    var body: some View {
        VStack {
            HStack {
                Toggle("shared_automatic_event_join_toggle".loco(), isOn: $automaticEventJoin)
                Picker("", selection: $automaticEventJoinTime) {
                    Text("general_when_event_starts".loco()).tag(TimeBeforeEvent.atStart)
                    Text("general_one_minute_before".loco()).tag(TimeBeforeEvent.minuteBefore)
                    Text("general_three_minute_before".loco()).tag(TimeBeforeEvent.threeMinuteBefore)
                    Text("general_five_minute_before".loco()).tag(TimeBeforeEvent.fiveMinuteBefore)
                }.frame(width: 220, alignment: .leading).labelsHidden().disabled(!automaticEventJoin)
            }

            if automaticEventJoin {
                Text("shared_automatic_event_join_tip".loco()).foregroundColor(.gray).font(.system(size: 12))
            }
        }
    }
}

struct FullscreenNotificationPicker: View {
    @Default(.fullscreenNotification) var fullscreenNotification
    @Default(.fullscreenNotificationTime) var fullscreenNotificationTime
    @Default(.fullscreenNotificationsForEventsWithoutMeetingLink)
    var fullscreenNotificationsForEventsWithoutMeetingLink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(
                    "shared_fullscreen_notification_toggle".loco(),
                    isOn: $fullscreenNotification
                )
                Picker("", selection: $fullscreenNotificationTime) {
                    Text("general_when_event_starts".loco()).tag(TimeBeforeEvent.atStart)
                    Text("general_one_minute_before".loco()).tag(TimeBeforeEvent.minuteBefore)
                    Text("general_three_minute_before".loco()).tag(TimeBeforeEvent.threeMinuteBefore)
                    Text("general_five_minute_before".loco()).tag(TimeBeforeEvent.fiveMinuteBefore)
                }
                .frame(width: 220, alignment: .leading)
                .labelsHidden()
                .disabled(!fullscreenNotification)
            }

            Toggle(
                "shared_fullscreen_notification_without_link_toggle".loco(),
                isOn: $fullscreenNotificationsForEventsWithoutMeetingLink
            )
            .disabled(!fullscreenNotification)
            .padding(.leading, 20)

            Text("shared_fullscreen_notification_without_link_help".loco())
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.leading, 20)
        }
    }
}

struct JoinEventNotificationPicker: View {
    @Default(.joinEventNotification) var joinEventNotification
    @Default(.joinEventNotificationTime) var joinEventNotificationTime

    var notificationSettings: (noAlertStyle: Bool, disabled: Bool) {
        checkNotificationSettings()
    }

    var body: some View {
        HStack {
            Toggle("shared_send_notification_toggle".loco(), isOn: $joinEventNotification)
            Picker("", selection: $joinEventNotificationTime) {
                Text("general_when_event_starts".loco()).tag(TimeBeforeEvent.atStart)
                Text("general_one_minute_before".loco()).tag(TimeBeforeEvent.minuteBefore)
                Text("general_three_minute_before".loco()).tag(TimeBeforeEvent.threeMinuteBefore)
                Text("general_five_minute_before".loco()).tag(TimeBeforeEvent.fiveMinuteBefore)
            }.frame(width: 220, alignment: .leading).labelsHidden().disabled(!joinEventNotification)
        }

        if joinEventNotification {
            if notificationSettings.noAlertStyle, !notificationSettings.disabled {
                Text("shared_send_notification_no_alert_style_tip".loco()).foregroundColor(.gray).font(.system(size: 12))
            }

            if notificationSettings.disabled {
                Text("shared_send_notification_disabled_tip".loco()).foregroundColor(.gray).font(.system(size: 12))
            }
        }
    }
}

struct EndEventNotificationPicker: View {
    @Default(.endOfEventNotification) var endOfEventNotification
    @Default(.endOfEventNotificationTime) var endOfEventNotificationTime

    var body: some View {
        HStack {
            Toggle("general_end_of_event_notification_toggle".loco(), isOn: $endOfEventNotification)
            Picker("", selection: $endOfEventNotificationTime) {
                Text("general_when_event_ends".loco()).tag(TimeBeforeEventEnd.atEnd)
                Text("general_one_minute_before".loco()).tag(TimeBeforeEventEnd.minuteBefore)
                Text("general_three_minute_before".loco()).tag(TimeBeforeEventEnd.threeMinuteBefore)
                Text("general_five_minute_before".loco()).tag(TimeBeforeEventEnd.fiveMinuteBefore)
            }.frame(width: 220, alignment: .leading).labelsHidden().disabled(!endOfEventNotification)
        }
    }
}

func checkNotificationSettings() -> (Bool, Bool) {
    let center = UNUserNotificationCenter.current()
    let group = DispatchGroup()
    let result = NotificationSettingsResult()
    group.enter()

    center.getNotificationSettings { notificationSettings in
        result.update(
            noAlertStyle: notificationSettings.alertStyle != .alert,
            notificationsDisabled: notificationSettings.authorizationStatus == .denied
        )
        group.leave()
    }

    group.wait()
    return result.value
}

/// `UNUserNotificationCenter.getNotificationSettings` invokes a Sendable
/// callback. This tiny holder keeps the synchronous Preferences helper
/// warning-free while the callback writes its result.
private final class NotificationSettingsResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = (noAlertStyle: false, notificationsDisabled: false)

    var value: (Bool, Bool) {
        lock.withLock { storedValue }
    }

    func update(noAlertStyle: Bool, notificationsDisabled: Bool) {
        lock.withLock {
            storedValue = (noAlertStyle, notificationsDisabled)
        }
    }
}

struct LaunchAtLoginANDPreferredLanguagePicker: View {
    @Default(.preferredLanguage) var preferredLanguage

    var body: some View {
        HStack {
            LaunchAtLogin.Toggle {
                Text("preferences_general_option_login_launch".loco())
            }
            Spacer()
            Picker("preferences_general_option_preferred_language_title".loco(), selection: $preferredLanguage) {
                Text("preferences_general_option_preferred_language_system_value".loco()).tag(AppLanguage.system)
                Section {
                    Group {
                        Text("English").tag(AppLanguage.english)
                        Text("Українська").tag(AppLanguage.ukrainian)
                        Text("Deutsch").tag(AppLanguage.german)
                        Text("Français").tag(AppLanguage.french)
                        Text("Hrvatski").tag(AppLanguage.croatian)
                        Text("Norsk").tag(AppLanguage.norwegian)
                        Text("Čeština").tag(AppLanguage.czech)
                        Text("日本語").tag(AppLanguage.japanese)
                        Text("Polski").tag(AppLanguage.polish)
                        Text("עברית‎").tag(AppLanguage.hebrew)
                    }
                    Group {
                        Text("Türkçe").tag(AppLanguage.turkish)
                        Text("Italiano").tag(AppLanguage.italian)
                        Text("Español").tag(AppLanguage.spanish)
                        Text("Português").tag(AppLanguage.portuguese)
                        Text("Slovenčina").tag(AppLanguage.slovak)
                        Text("Nederlands").tag(AppLanguage.dutch)
                    }
                }
            }.frame(width: 250)
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        AutomaticEventJoinPicker()
        Divider()
        FullscreenNotificationPicker()
        Divider()
        JoinEventNotificationPicker()
        Divider()
        EndEventNotificationPicker()
        Divider()
        LaunchAtLoginANDPreferredLanguagePicker()
    }.padding()
}
