//
//  PreferencesView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var patronageService: PatronageService
    @State private var selectedTab = PreferencesTab.defaultSelection

    var body: some View {
        HStack(spacing: 0) {
            List {
                ForEach(PreferencesTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.titleKey.loco(), systemImage: tab.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 5)
                            .padding(.horizontal, 7)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .padding(.horizontal, 6)
                    )
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 190, maxWidth: 220)

            Divider()

            GeometryReader { geometry in
                ScrollView {
                    tabContent(selectedTab)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: max(0, geometry.size.height - 40),
                            alignment: .topLeading
                        )
                        .padding(20)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
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

#Preview {
    PreferencesView(patronageService: PatronageService())
        .frame(width: 700, height: 620)
}
