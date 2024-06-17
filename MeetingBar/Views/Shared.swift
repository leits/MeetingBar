//
//  Shared.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
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

struct FullscreenNotificationPicker: View {
    @Default(.fullscreenNotification) var fullscreenNotification
    @Default(.fullscreenNotificationTime) var fullscreenNotificationTime

    var body: some View {
        HStack {
            Toggle("shared_fullscreen_notification_toggle".loco(), isOn: $fullscreenNotification)
            Picker("", selection: $fullscreenNotificationTime) {
                Text("general_when_event_starts".loco()).tag(TimeBeforeEvent.atStart)
                Text("general_one_minute_before".loco()).tag(TimeBeforeEvent.minuteBefore)
                Text("general_three_minute_before".loco()).tag(TimeBeforeEvent.threeMinuteBefore)
                Text("general_five_minute_before".loco()).tag(TimeBeforeEvent.fiveMinuteBefore)
            }.frame(width: 220, alignment: .leading).labelsHidden().disabled(!fullscreenNotification)
        }
    }
}

struct JoinEventNotificationPicker: View {
    @Default(.joinEventNotification) var joinEventNotification
    @Default(.joinEventNotificationTime) var joinEventNotificationTime

    let (noAlertStyle, disabled) = checkNotificationSettings()

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

        if noAlertStyle, !disabled, joinEventNotification {
            Text("shared_send_notification_no_alert_style_tip".loco()).foregroundColor(.gray).font(.system(size: 12))
        }

        if disabled, joinEventNotification {
            Text("shared_send_notification_disabled_tip".loco()).foregroundColor(.gray).font(.system(size: 12))
        }
    }
}
struct endEventNotificationPicker: View {
    @Default(.endOfEventNotification) var endOfEventNotification
    @Default(.endOfEventNotificationTime) var endOfEventNotificationTime

    var body: some View {
        HStack {
            Toggle("Sent a notification when event ends", isOn: $endOfEventNotification)
            Picker("", selection: $endOfEventNotificationTime) {
                Text("when event ends").tag(TimeBeforeEventEnd.atEnd)
                Text("1 minute before").tag(TimeBeforeEventEnd.minuteBefore)
                Text("3 minute before").tag(TimeBeforeEventEnd.threeMinuteBefore)
                Text("5 minute before").tag(TimeBeforeEventEnd.fiveMinuteBefore)
            }.frame(width: 220, alignment: .leading).labelsHidden().disabled(!endOfEventNotification)
            Text("βeta").font(.caption).foregroundColor(.orange)
        }

    }
}

func checkNotificationSettings() -> (Bool, Bool) {
    var noAlertStyle = false
    var notificationsDisabled = false

    let center = UNUserNotificationCenter.current()
    let group = DispatchGroup()
    group.enter()

    center.getNotificationSettings { notificationSettings in
        noAlertStyle = notificationSettings.alertStyle != UNAlertStyle.alert
        notificationsDisabled = notificationSettings.authorizationStatus == UNAuthorizationStatus.denied
        group.leave()
    }

    group.wait()
    return (noAlertStyle, notificationsDisabled)
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
                        Text("Deutsche").tag(AppLanguage.german)
                        Text("Français").tag(AppLanguage.french)
                        Text("Hrvatski").tag(AppLanguage.croatian)
                        Text("Norks").tag(AppLanguage.norwegian)
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
                        Text("Nederland").tag(AppLanguage.dutch)
                    }
                }
            }.frame(width: 250)
        }
    }
}
