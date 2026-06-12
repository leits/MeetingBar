//
//  NotificationsTab.swift
//  MeetingBar
//

import SwiftUI

struct NotificationsTab: View {
    var body: some View {
        PreferencesGroupedForm {
            Section(header: Text("preferences_notifications_alerts_title".loco())) {
                JoinEventNotificationPicker()
            }

            Section {
                FullscreenNotificationPicker()
            }

            Section {
                EndEventNotificationPicker()
            }

            Section(header: Text("preferences_notifications_automation_title".loco())) {
                AutomaticEventJoinPicker()
            }
        }
    }
}
