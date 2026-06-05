//
//  CalendarsScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

struct CalendarsScreen: View {
    @ObservedObject var router: OnboardingRouter
    @EnvironmentObject var onboardingHandler: OnboardingHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("onboarding_calendar_selection_title".loco())
                .font(.title2)
                .bold()
            Text("onboarding_calendar_selection_description".loco())
                .foregroundStyle(.secondary)

            if let appModel = onboardingHandler.appModel {
                CalendarSelectionContent(appModel: appModel)
            } else {
                ProgressView()
            }

            HStack {
                Spacer()
                if onboardingHandler.appModel?.state.selectedCalendarIDs.isEmpty != false {
                    Text("calendars_screen_select_calendar_title".loco()).foregroundColor(
                        Color.gray)
                }
                Button("onboarding_continue".loco()) {
                    router.currentStep = .meetingOpening
                }
                .buttonStyle(.borderedProminent)
                .disabled(onboardingHandler.appModel?.state.selectedCalendarIDs.isEmpty != false)
            }
        }
    }
}

private struct CalendarSelectionContent: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        GroupBox {
            if appModel.state.calendars.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: emptyStateIcon)
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(emptyStateText)
                    Button("general_refresh".loco()) {
                        appModel.send(.refreshCalendars)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    CalendarSectionsView(calendars: appModel.state.calendars)
                }
                .listStyle(.inset)
            }
        }
        .environmentObject(appModel)
    }

    private var emptyStateIcon: String {
        appModel.state.providerHealth.authRequired
            ? "person.crop.circle.badge.exclamationmark"
            : "calendar.badge.exclamationmark"
    }

    private var emptyStateText: String {
        if appModel.state.providerHealth.authRequired {
            return "onboarding_calendar_selection_reconnect".loco()
        }
        if appModel.state.activeProvider == .macOSEventKit,
           appModel.state.providerHealth.lastErrorDescription != nil {
            return "onboarding_calendar_selection_permission".loco()
        }
        return "onboarding_calendar_selection_empty".loco()
    }
}
