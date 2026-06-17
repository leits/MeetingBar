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

            OnboardingFooter(
                onBack: { router.currentStep = .calendarSource },
                hint: canContinue ? nil : "calendars_screen_select_calendar_title".loco(),
                primaryTitle: "onboarding_continue".loco(),
                primaryEnabled: canContinue,
                primaryAction: { router.currentStep = .meetingOpening }
            )
        }
    }

    private var canContinue: Bool {
        OnboardingFlowPolicy.canContinueCalendarSelection(
            selectedCalendarIDs: onboardingHandler.appModel?.state.selectedCalendarIDs ?? [],
            availableCalendarIDs: onboardingHandler.appModel?.state.calendars.map(\.id) ?? []
        )
    }
}

private struct CalendarSelectionContent: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        let presentation = PreferencesCalendarPresentation.make(from: appModel.state)

        GroupBox {
            if appModel.state.calendars.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: emptyStateIcon)
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(emptyStateText)
                        .multilineTextAlignment(.center)
                    HStack {
                        if presentation.canReconnect {
                            Button("preferences_status_reconnect".loco()) {
                                appModel.send(
                                    .changeProvider(presentation.activeProvider, signOut: true)
                                )
                            }
                        }
                        if presentation.canOpenCalendarSettings {
                            Button("preferences_status_open_calendar_settings".loco()) {
                                NSWorkspace.shared.open(Links.calendarPreferences)
                            }
                        }
                        Button("general_refresh".loco()) {
                            appModel.send(.refreshCalendars)
                        }
                    }
                    .disabled(appModel.state.providerChangeInProgress)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    CalendarSectionsView(calendars: appModel.state.calendars)
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
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
