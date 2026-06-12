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
                ForEach(PreferencesSidebarSection.allCases, id: \.self) { section in
                    Section(header: Text(section.titleKey.loco())) {
                        ForEach(section.tabs, id: \.self) { tab in
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
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 190, maxWidth: 220)

            Divider()

            tabContent(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Shared container for preferences tabs: a grouped form matching the
/// System Settings look on macOS 13+, with a plain scrollable form as the
/// macOS 12 fallback. Tabs built on this manage their own scrolling.
struct PreferencesGroupedForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 13.0, *) {
            Form { content }
                .formStyle(.grouped)
        } else {
            ScrollView {
                Form { content }
                    .padding(20)
            }
        }
    }
}

#Preview {
    PreferencesView(patronageService: PatronageService())
        .frame(width: 860, height: 620)
}
