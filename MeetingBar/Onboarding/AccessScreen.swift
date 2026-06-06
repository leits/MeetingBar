//
//  AccessScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import AppKit
import SwiftUI

struct AccessScreen: View {
    @ObservedObject var router: OnboardingRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("onboarding_calendar_source_title".loco())
                .font(.title2)
                .bold()
            Text("onboarding_calendar_source_description".loco())
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ForEach(CalendarSourcePresentation.all) { source in
                    ProviderChoice(source: source) {
                        router.selectProvider(source.provider)
                    }
                }
            }
            Spacer()
        }
    }
}

private struct ProviderChoice: View {
    let source: CalendarSourcePresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: source.systemImage).font(.title)
                Text(source.titleKey.loco()).font(.headline)
                Text(source.descriptionKey.loco())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        source.dataSourceKey.loco(),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    Label(source.accountScopeKey.loco(), systemImage: "person.2")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()
                Text("onboarding_use_calendar_source".loco()).fontWeight(.semibold)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }
}

struct AuthorizationScreen: View {
    @ObservedObject var router: OnboardingRouter
    @EnvironmentObject var onboardingHandler: OnboardingHandler

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("onboarding_authorization_title".loco())
                .font(.title2)
                .bold()
            Text(authorizationDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch router.authorizationState {
            case .idle, .requesting:
                ProgressView()
                Text("onboarding_authorization_waiting".loco())
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title)
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("onboarding_choose_different_source".loco()) {
                        router.selectedProvider = nil
                        router.authorizationState = .idle
                        router.currentStep = .calendarSource
                    }
                    if router.selectedProvider == .macOSEventKit {
                        Button("access_screen_access_denied_system_preferences_button".loco()) {
                            NSWorkspace.shared.open(Links.calendarPreferences)
                        }
                    }
                    Button("access_screen_try_again".loco()) {
                        Task { await authorize() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .task(id: router.selectedProvider) {
            if router.authorizationState == .idle {
                await authorize()
            }
        }
    }

    private var authorizationDescription: String {
        guard let provider = router.selectedProvider else {
            return "onboarding_authorization_apple_description".loco()
        }
        return CalendarSourcePresentation.make(for: provider)
            .authorizationDescriptionKey
            .loco()
    }

    private func authorize() async {
        guard let provider = router.selectedProvider else {
            router.currentStep = .calendarSource
            return
        }
        router.authorizationState = .requesting
        let result = await onboardingHandler.onProviderSelected(provider)

        if result == .success {
            router.currentStep = .calendarSelection
        } else if let state = OnboardingFlowPolicy.authorizationState(for: result) {
            router.authorizationState = state
        }
    }
}
