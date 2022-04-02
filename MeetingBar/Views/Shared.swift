//
//  Shared.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
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
                Text("shared_automatic_event_join_directly_value".loco()).tag(AutomaticEventJoinTime.atStart)
                Text("shared_automatic_event_join_one_minute_value".loco()).tag(AutomaticEventJoinTime.minuteBefore)
                Text("shared_automatic_event_join_two_minutes_value".loco()).tag(AutomaticEventJoinTime.twoMinutesBefore)
                Text("shared_automatic_event_join_three_minutes_value".loco()).tag(AutomaticEventJoinTime.threeMinutesBefore)
                Text("shared_automatic_event_join_four_minutes_value".loco()).tag(AutomaticEventJoinTime.fourMinutesBefore)
                Text("shared_automatic_event_join_five_minutes_value".loco()).tag(AutomaticEventJoinTime.fiveMinutesBefore)
                Text("shared_automatic_event_join_ten_minutes_value".loco()).tag(AutomaticEventJoinTime.tenMinutesBefore)
            }.frame(width: 220, alignment: .leading).labelsHidden().disabled(!automaticEventJoin)
        }

        if automaticEventJoin {
            Text("shared_automatic_event_join_tip".loco()).foregroundColor(Color.gray).font(.system(size: 12))
        }
    }
}

struct JoinEventNotificationPicker: View {
    @Default(.joinEventNotification) var joinEventNotification
    @Default(.joinEventNotificationTime) var joinEventNotificationTime

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

    var body: some View {
        HStack {
            Toggle("shared_send_notification_toggle".loco(), isOn: $joinEventNotification)
            Picker("", selection: $joinEventNotificationTime) {
                Text("shared_send_notification_directly_value".loco()).tag(JoinEventNotificationTime.atStart)
                Text("shared_send_notification_one_minute_value".loco()).tag(JoinEventNotificationTime.minuteBefore)
                Text("shared_send_notification_three_minute_value".loco()).tag(JoinEventNotificationTime.threeMinuteBefore)
                Text("shared_send_notification_five_minute_value".loco()).tag(JoinEventNotificationTime.fiveMinuteBefore)
            }.frame(width: 220, alignment: .leading).labelsHidden().disabled(!joinEventNotification)
        }
        let (noAlertStyle, disabled) = checkNotificationSettings()

        if noAlertStyle && !disabled && joinEventNotification {
            Text("shared_send_notification_no_alert_style_tip".loco()).foregroundColor(Color.gray).font(.system(size: 12))
        }

        if disabled && joinEventNotification {
            Text("shared_send_notification_disabled_tip".loco()).foregroundColor(Color.gray).font(.system(size: 12))
        }
    }
}

struct LaunchAtLoginANDPreferredLanguagePicker: View {
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.preferredLanguage) var preferredLanguage

    var body: some View {
        HStack {
            Toggle("preferences_general_option_login_launch".loco(), isOn: $launchAtLogin)
            Spacer()
            Picker("preferences_general_option_preferred_language_title".loco(), selection: $preferredLanguage) {
                Text("preferences_general_option_preferred_language_system_value".loco()).tag(AppLanguage.system)
                Section {
                    Group {
                        Text("English").tag(AppLanguage.english)
                        Text("Українська").tag(AppLanguage.ukrainian)
                        Text("Hrvatski").tag(AppLanguage.croatian)
                        Text("Français").tag(AppLanguage.french)
                        Text("Deutsche").tag(AppLanguage.german)
                        Text("Norks").tag(AppLanguage.norwegian)
                        Text("Čeština").tag(AppLanguage.czech)
                        Text("日本語").tag(AppLanguage.japanese)
                        Text("Polskie").tag(AppLanguage.polish)
                        Text("עברית‎").tag(AppLanguage.hebrew)
                    }
                    Group {
                        Text("Русский").tag(AppLanguage.russian)
                        Text("Türkçe").tag(AppLanguage.turkish)
                    }
                }
            }.frame(width: 250)
        }
    }
}
