//
//  WelcomeScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

struct WelcomeScreen: View {
    @ObservedObject var router: OnboardingRouter

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
            Text("onboarding_welcome_title".loco())
                .font(.largeTitle)
                .bold()
            Text("onboarding_welcome_description".loco())
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Spacer()
            OnboardingFooter(
                primaryTitle: "onboarding_continue".loco(),
                primaryAction: { router.currentStep = .calendarSource }
            )
        }
    }
}
