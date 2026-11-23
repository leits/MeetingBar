//
//  NotificationsTab.swift
//  MeetingBar
//

import SwiftUI

struct NotificationsTab: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        PreferencesGroupedForm {
            Section(header: Text("preferences_notifications_alerts_title".loco())) {
                JoinEventNotificationPicker()
            }

            Section {
                FullscreenNotificationPicker()

                HStack {
                    Spacer()
                    Button("preferences_notifications_fullscreen_preview_button".loco()) {
                        appModel.send(.previewFullscreenNotification)
                    }
                    .disabled(appModel.nextEvent() == nil)
                }
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
