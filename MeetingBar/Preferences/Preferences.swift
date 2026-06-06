//
//  PreferencesView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject var patronageService: PatronageService

    var body: some View {
        TabView {
            ForEach(PreferencesTab.allCases, id: \.self) { tab in
                tabContent(tab)
                    .tabItem {
                        Label(tab.titleKey.loco(), systemImage: tab.systemImage)
                    }
            }
        }.padding()
    }

    @ViewBuilder
    private func tabContent(_ tab: PreferencesTab) -> some View {
        switch tab {
        case .general:
            GeneralTab(patronageService: patronageService)
        case .calendars:
            CalendarsTab()
        case .meetingOpening:
            LinksTab()
        case .menuBar:
            AppearanceTab()
        case .notifications:
            NotificationsTab()
        case .advanced:
            AdvancedTab()
        case .status:
            StatusTab()
        }
    }
}
