//
//  OnboardingView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import Combine
import SwiftUI

/// Setup steps the onboarding flow walks through. Future steps (notification
/// permission, post-setup recap, etc.) can be inserted without changing how
/// individual screens drive the transition.
enum OnboardingStep: Hashable {
    case welcome
    case calendarSource
    case authorization
    case calendarSelection
    case meetingOpening
    case success
}

enum OnboardingAuthorizationState: Equatable {
    case idle
    case requesting
    case failed(String)
}

enum OnboardingFlowPolicy {
    static func canContinueCalendarSelection(
        selectedCalendarIDs: [String],
        availableCalendarIDs: [String]
    ) -> Bool {
        !Set(selectedCalendarIDs).isDisjoint(with: availableCalendarIDs)
    }

    static func authorizationState(
        for result: ProviderSelectionResult
    ) -> OnboardingAuthorizationState? {
        switch result {
        case .success:
            return nil
        case .cancelled:
            return .failed("access_screen_provider_authorization_cancelled".loco())
        case .authRequired(let description), .failed(let description):
            return .failed(description)
        }
    }
}

@MainActor
final class OnboardingRouter: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var selectedProvider: EventStoreProvider?
    @Published var authorizationState: OnboardingAuthorizationState = .idle

    func selectProvider(_ provider: EventStoreProvider) {
        selectedProvider = provider
        authorizationState = .idle
        currentStep = .authorization
    }
}

struct OnboardingView: View {
    @StateObject private var router = OnboardingRouter()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MeetingBar Setup")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { NSApplication.shared.keyWindow?.close() }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            VStack(alignment: .leading) {
                OnboardingProgress(step: router.currentStep)
                Divider()
                switch router.currentStep {
                case .welcome:
                    WelcomeScreen(router: router)
                case .calendarSource:
                    AccessScreen(router: router)
                case .authorization:
                    AuthorizationScreen(router: router)
                case .calendarSelection:
                    CalendarsScreen(router: router)
                case .meetingOpening:
                    MeetingOpeningScreen(router: router)
                case .success:
                    OnboardingSuccessScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
    }
}

private struct OnboardingProgress: View {
    let step: OnboardingStep

    private var index: Int {
        switch step {
        case .welcome: 1
        case .calendarSource: 2
        case .authorization: 3
        case .calendarSelection: 4
        case .meetingOpening: 5
        case .success: 6
        }
    }

    var body: some View {
        HStack {
            Text("onboarding_progress".loco("\(index)", "6"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct MeetingOpeningScreen: View {
    @ObservedObject var router: OnboardingRouter
    @EnvironmentObject var onboardingHandler: OnboardingHandler
    @State private var isCompleting = false
    @State private var errorMessage: String?

    private let providers = [
        MeetingProvider.provider(for: .meet),
        MeetingProvider.provider(for: .zoom),
        MeetingProvider.provider(for: .teams)
    ].compactMap { $0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("onboarding_meeting_opening_title".loco())
                .font(.title2)
                .bold()
            Text("onboarding_meeting_opening_description".loco())
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(providers, id: \.id) { provider in
                        MeetingProviderOpeningPicker(provider: provider, labelWidth: 150)
                    }
                }
                .padding(8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Spacer()
            HStack {
                Spacer()
                if isCompleting {
                    ProgressView().controlSize(.small)
                }
                Button("onboarding_continue".loco()) {
                    Task { await complete() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCompleting)
            }
        }
    }

    private func complete() async {
        guard let provider = router.selectedProvider else { return }
        isCompleting = true
        errorMessage = nil
        let result = await onboardingHandler.onComplete(provider)
        isCompleting = false

        switch result {
        case .success:
            router.currentStep = .success
        case .cancelled:
            errorMessage = "access_screen_provider_authorization_cancelled".loco()
        case .authRequired(let message), .failed(let message):
            errorMessage = message
        }
    }
}

private struct OnboardingSuccessScreen: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("onboarding_success_title".loco())
                .font(.title)
                .bold()
            Text("onboarding_success_description".loco())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            HStack {
                Spacer()
                Button("onboarding_done".loco()) {
                    NSApplication.shared.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
