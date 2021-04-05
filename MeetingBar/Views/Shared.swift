//
//  Shared.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI
import Defaults
import UserNotifications

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
            Toggle("Send notification to join next event meeting", isOn: $joinEventNotification)
            Picker("", selection: $joinEventNotificationTime) {
                Text("when event starts").tag(JoinEventNotificationTime.atStart)
                Text("1 minute before").tag(JoinEventNotificationTime.minuteBefore)
                Text("3 minutes before").tag(JoinEventNotificationTime.threeMinuteBefore)
                Text("5 minutes before").tag(JoinEventNotificationTime.fiveMinuteBefore)
            }.frame(width: 150, alignment: .leading).labelsHidden().disabled(!joinEventNotification)
        }
        let (noAlertStyle, disabled) = checkNotificationSettings()

        if noAlertStyle && !disabled && joinEventNotification {
            Text("⚠️ Your macos notification settings for Meetingbar are currently not set to alert. Please activate alerts if you want to have persistent notifications.").foregroundColor(Color.gray).font(.system(size: 12))
        }

        if disabled && joinEventNotification {
            Text("⚠️ Your macos notification settings for Meetingbar are currently off. Please enable the notifications in macos system settings to do not miss a meeting.").foregroundColor(Color.gray).font(.system(size: 12))
        }
    }
}
