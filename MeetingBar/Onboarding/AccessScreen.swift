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
                    ProviderChoice(
                        source: source,
                        isSelected: router.selectedProvider == source.provider
                    ) {
                        // Clicking a card only selects it; advancing to
                        // authorization is a separate, explicit Continue press.
                        router.selectedProvider = source.provider
                    }
                }
            }
            Spacer()
            OnboardingFooter(
                onBack: { router.currentStep = .welcome },
                primaryTitle: "onboarding_continue".loco(),
                primaryEnabled: router.selectedProvider != nil,
                primaryAction: {
                    guard let provider = router.selectedProvider else { return }
                    router.selectProvider(provider)
                }
            )
        }
    }
}

private struct ProviderChoice: View {
    let source: CalendarSourcePresentation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: source.systemImage).font(.title)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                Text(source.titleKey.loco()).font(.headline)
                Text(source.descriptionKey.loco())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)

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
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
