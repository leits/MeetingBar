//
//  NotificationsTab.swift
//  MeetingBar
//

import SwiftUI

struct NotificationsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            GroupBox(
                label: Label(
                    "preferences_notifications_alerts_title".loco(),
                    systemImage: "bell.badge")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    JoinEventNotificationPicker()
                    FullscreenNotificationPicker()
                    EndEventNotificationPicker()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox(
                label: Label(
                    "preferences_notifications_automation_title".loco(),
                    systemImage: "play.circle")
            ) {
                AutomaticEventJoinPicker()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }

            Spacer()
        }
    }
}
