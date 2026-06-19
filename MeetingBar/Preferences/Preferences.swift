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
    // Non-optional: a settings window always has exactly one active tab.
    // An optional selection binding let NavigationSplitView seed the sidebar
    // highlight out of sync with the detail on first appearance.
    @State private var selectedTab: PreferencesTab = .defaultSelection

    var body: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
            } detail: {
                tabContent(selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selectedTab.titleKey.loco())
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 760, minHeight: 520)
        } else {
            legacyLayout
        }
    }

    // The native sidebar list: `List(selection:)` provides the System Settings
    // accent-pill selection and translucent material for free, so the custom
    // Button / listRowBackground styling the legacy layout needs is gone here.
    @available(macOS 13.0, *)
    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(PreferencesSidebarSection.allCases, id: \.self) { section in
                Section(section.titleKey.loco()) {
                    ForEach(section.tabs, id: \.self) { tab in
                        Label(tab.titleKey.loco(), systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // macOS 12 fallback: NavigationSplitView is unavailable, so keep the manual
    // split with hand-rolled selection styling.
    private var legacyLayout: some View {
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

/// Returns a row label for the given localization key with any trailing
/// colon removed. Legacy strings include colons ("All-day events:") that the
/// grouped-form layout doesn't use; trimming at presentation level keeps all
/// locales consistent without touching translation files.
func preferenceLabel(_ key: String) -> String {
    var label = key.loco().trimmingCharacters(in: .whitespaces)
    while let last = label.last, last == ":" || last == "：" {
        label.removeLast()
    }
    return label
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
