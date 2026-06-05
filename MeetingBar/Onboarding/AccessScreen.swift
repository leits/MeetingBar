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
                ProviderChoice(
                    title: "onboarding_apple_calendar_title".loco(),
                    description: "onboarding_apple_calendar_description".loco(),
                    systemImage: "calendar",
                    action: { router.selectProvider(.macOSEventKit) }
                )
                ProviderChoice(
                    title: "onboarding_google_calendar_title".loco(),
                    description: "onboarding_google_calendar_description".loco(),
                    systemImage: "globe",
                    action: { router.selectProvider(.googleCalendar) }
                )
            }
            Spacer()
        }
    }
}

private struct ProviderChoice: View {
    let title: String
    let description: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage).font(.title)
                Text(title).font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text("onboarding_connect".loco()).fontWeight(.semibold)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
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
        router.selectedProvider == .googleCalendar
            ? "onboarding_authorization_google_description".loco()
            : "onboarding_authorization_apple_description".loco()
    }

    private func authorize() async {
        guard let provider = router.selectedProvider else {
            router.currentStep = .calendarSource
            return
        }
        router.authorizationState = .requesting
        let result = await onboardingHandler.onProviderSelected(provider)

        switch result {
        case .success:
            router.currentStep = .calendarSelection
        case .cancelled:
            router.authorizationState = .failed(
                "access_screen_provider_authorization_cancelled".loco()
            )
        case .authRequired(let description):
            router.authorizationState = .failed(description)
        case .failed(let description):
            router.authorizationState = .failed(description)
        }
    }
}
