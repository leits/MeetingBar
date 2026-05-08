//
//  OnboardingView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import Combine

import SwiftUI

enum Screens {
    case welcome
    case access
    case calendars
}

class ViewRouter: ObservableObject {
    let objectWillChange = PassthroughSubject<ViewRouter, Never>()

    var currentScreen: Screens = .welcome {
        didSet {
            objectWillChange.send(self)
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var viewRouter = ViewRouter()

    var body: some View {
        VStack(alignment: .leading) {
            if viewRouter.currentScreen == .welcome {
                WelcomeScreen(viewRouter: viewRouter).padding()
            }
            if viewRouter.currentScreen == .access {
                AccessScreen(viewRouter: viewRouter).padding()
            }
            if viewRouter.currentScreen == .calendars {
                CalendarsScreen().padding()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}
