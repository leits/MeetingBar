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

/// Maps a step to its position among the user-facing setup stages. The
/// authorization step shares stage 2 with source selection (it runs
/// automatically), and `success` is terminal, so neither shows a distinct
/// progress position.
enum OnboardingProgressPolicy {
    static let totalStages = 4

    static func stageIndex(for step: OnboardingStep) -> Int? {
        switch step {
        case .welcome: 1
        case .calendarSource, .authorization: 2
        case .calendarSelection: 3
        case .meetingOpening: 4
        case .success: nil
        }
    }
}

struct OnboardingView: View {
    @StateObject private var router = OnboardingRouter()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("onboarding_setup_title".loco())
                    .font(.headline)
                    .foregroundStyle(.secondary)
                OnboardingProgress(step: router.currentStep)
                Spacer()
                Button(action: { NSApplication.shared.keyWindow?.close() }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("general_close".loco())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(alignment: .leading) {
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

/// Slim segmented progress shown in the window header. Filled segments mark
/// completed and current stages; the textual "Step X of Y" is preserved as the
/// accessibility label.
private struct OnboardingProgress: View {
    let step: OnboardingStep

    var body: some View {
        if let index = OnboardingProgressPolicy.stageIndex(for: step) {
            let total = OnboardingProgressPolicy.totalStages
            HStack(spacing: 5) {
                ForEach(1 ... total, id: \.self) { stage in
                    Capsule()
                        .fill(stage <= index ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 18, height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("onboarding_progress".loco("\(index)", "\(total)")))
        }
    }
}

/// Shared footer for onboarding screens: an optional Back button on the
/// leading edge and an optional primary action on the trailing edge, with an
/// optional inline hint and busy spinner. Keeps navigation consistent across
/// every step instead of each screen hand-rolling its own button row.
struct OnboardingFooter: View {
    var onBack: (() -> Void)?
    var hint: String?
    var isBusy: Bool = false
    var primaryTitle: String?
    var primaryEnabled: Bool = true
    var primaryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button("onboarding_back".loco(), action: onBack)
            }
            Spacer()
            if let hint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if isBusy {
                ProgressView().controlSize(.small)
            }
            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!primaryEnabled || isBusy)
            }
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
            OnboardingFooter(
                onBack: { router.currentStep = .calendarSelection },
                isBusy: isCompleting,
                primaryTitle: "onboarding_continue".loco(),
                primaryAction: { Task { await complete() } }
            )
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
            OnboardingFooter(
                primaryTitle: "onboarding_done".loco(),
                primaryAction: { NSApplication.shared.keyWindow?.close() }
            )
        }
    }
}
