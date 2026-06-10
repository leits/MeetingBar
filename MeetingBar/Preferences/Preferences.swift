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
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MeetingBar").font(.system(size: 15, weight: .semibold))
                        Text("Preferences").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            HStack(spacing: 0) {
                List {
                    ForEach(PreferencesSidebarSection.allCases, id: \.self) { section in
                        Section(header: Text(section.titleKey.loco()).font(.system(size: 12, weight: .semibold)).textCase(.uppercase).foregroundStyle(.secondary)) {
                            ForEach(section.tabs, id: \.self) { tab in
                                Button {
                                    selectedTab = tab
                                } label: {
                                    Label(tab.titleKey.loco(), systemImage: tab.systemImage)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                                        .padding(.horizontal, 6)
                                )
                            }
                        }
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
                            .padding(24)
                    }
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
        }
    }
}

#Preview {
    PreferencesView(patronageService: PatronageService())
        .frame(width: 860, height: 620)
}
