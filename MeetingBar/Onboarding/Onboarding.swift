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
    case calendarAccess
    case calendarSelection
}

@MainActor
final class OnboardingRouter: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
}

struct OnboardingView: View {
    @StateObject private var router = OnboardingRouter()

    var body: some View {
        VStack(alignment: .leading) {
            switch router.currentStep {
            case .welcome:
                WelcomeScreen(router: router).padding()
            case .calendarAccess:
                AccessScreen(router: router).padding()
            case .calendarSelection:
                CalendarsScreen().padding()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}
