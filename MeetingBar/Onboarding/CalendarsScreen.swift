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
                // Observe appModel here so the footer's enabled state recomputes
                // when a calendar is toggled (CalendarsScreen itself only
                // observes the router and handler, which don't change on toggle).
                CalendarSelectionStep(router: router, appModel: appModel)
            } else {
                ProgressView()
                Spacer()
                OnboardingFooter(onBack: { router.currentStep = .calendarSource })
            }
        }
    }
}

private struct CalendarSelectionStep: View {
    @ObservedObject var router: OnboardingRouter
    @ObservedObject var appModel: AppModel

    var body: some View {
        CalendarSelectionContent(appModel: appModel)

        OnboardingFooter(
            onBack: { router.currentStep = .calendarSource },
            hint: canContinue ? nil : "calendars_screen_select_calendar_title".loco(),
            primaryTitle: "onboarding_continue".loco(),
            primaryEnabled: canContinue,
            primaryAction: { router.currentStep = .essentials }
        )
    }

    private var canContinue: Bool {
        OnboardingFlowPolicy.canContinueCalendarSelection(
            selectedCalendarIDs: appModel.state.selectedCalendarIDs,
            availableCalendarIDs: appModel.state.calendars.map(\.id)
        )
    }
}

private struct CalendarSelectionContent: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        // Same grouped-form presentation as Preferences → Calendars, so the
        // selection list looks identical in both places.
        PreferencesGroupedForm {
            if appModel.state.calendars.isEmpty {
                Section {
                    emptyState
                }
            } else {
                CalendarSectionsView(calendars: appModel.state.calendars)
            }
        }
        .environmentObject(appModel)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        let presentation = PreferencesCalendarPresentation.make(from: appModel.state)
        VStack(spacing: 10) {
            Image(systemName: emptyStateIcon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(emptyStateText)
                .multilineTextAlignment(.center)
            HStack {
                if presentation.canReconnect {
                    Button("preferences_status_reconnect".loco()) {
                        appModel.send(.changeProvider(presentation.activeProvider, signOut: true))
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
