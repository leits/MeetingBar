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
    @EnvironmentObject var onboardingHandler: OnboardingHandler
    @State var providerSelected = false
    @State var requestFailed = false
    @State private var selectedProvider: EventStoreProvider?
    @State private var statusMessage: String?
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .center) {
            if !providerSelected {
                Text("access_screen_provider_picker_label".loco()).font(.title).bold().padding(
                    .bottom, 30)
                HStack(alignment: .top) {
                    VStack(spacing: 10) {
                        List {
                            Section(
                                header:
                                    Text("access_screen_provider_macos_title".loco()).font(
                                        .headline)
                            ) {
                                Text("access_screen_provider_macos_data_source".loco())
                                Text("access_screen_provider_macos_number_of_accounts".loco())
                                Text("access_screen_provider_macos_recommended".loco())
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        VStack {
                            Button(action: {
                                Task { await requestAccess(provider: .macOSEventKit) }
                            }) {
                                Text("Use macOS Calendar").font(.headline)
                            }
                        }.frame(width: 200, height: 50)
                    }
                    VStack(spacing: 10) {
                        List {
                            Section(header: Text("Google Calendar API").font(.headline)) {
                                Text("access_screen_provider_gcalendar_data_source".loco())
                                Text("access_screen_provider_gcalendar_number_of_accounts".loco())
                            }
                        }
                        Spacer()
                        VStack {
                            Button(
                                action: { Task { await requestAccess(provider: .googleCalendar) } },
                                label: {
                                    Image("googleSignInButton").resizable().aspectRatio(
                                        contentMode: .fit
                                    ).frame(width: 150)
                                }
                            ).buttonStyle(PlainButtonStyle())
                        }.frame(width: 200, height: 50)
                    }
                }
            } else {
                Spacer()
                if selectedProvider == .googleCalendar {
                    VStack(spacing: 20) {
                        Text("access_screen_provider_gcalendar_sign_in_title".loco()).bold()
                        Text("access_screen_provider_gcalendar_sign_in_description".loco())
                        if let statusMessage {
                            Text(statusMessage).foregroundColor(.red)
                        }
                        if isRequesting {
                            ProgressView()
                        }
                        Button("access_screen_try_again".loco()) {
                            Task { await requestAccess(provider: .googleCalendar) }
                        }.disabled(isRequesting)
                    }
                } else {
                    if !requestFailed {
                        Text("access_screen_access_granted_title".loco())
                        Text("")
                        Text("access_screen_access_granted_click_ok_title".loco())
                    } else {
                        VStack(alignment: .center, spacing: 10) {
                            HStack {
                                Text("access_screen_access_screen_access_denied_go_to_title".loco())
                                Button(
                                    "access_screen_access_denied_system_preferences_button".loco()
                                ) { NSWorkspace.shared.open(Links.calendarPreferences) }
                                Text("access_screen_access_denied_checkbox_title".loco())
                            }
                            Text("access_screen_access_denied_relaunch_title".loco())
                            if let statusMessage {
                                Text(statusMessage).foregroundColor(.red)
                            }
                        }
                    }
                }
                Spacer()
            }
        }.padding()
    }

    @MainActor
    func requestAccess(provider: EventStoreProvider) async {
        providerSelected = true
        selectedProvider = provider
        requestFailed = false
        statusMessage = nil
        isRequesting = true
        let result = await onboardingHandler.onProviderSelected(provider)
        isRequesting = false

        switch result {
        case .success:
            router.currentStep = .calendarSelection
        case .cancelled:
            requestFailed = true
            statusMessage = "access_screen_provider_authorization_cancelled".loco()
        case .authRequired(let description):
            requestFailed = true
            statusMessage = description
        case .failed(let description):
            requestFailed = true
            statusMessage = description
        }
    }
}
