//
//  GeneralTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults
import KeyboardShortcuts

struct GeneralTab: View {
    @ObservedObject var patronageService: PatronageService
    @Default(.timeFormat) var timeFormat

    var body: some View {
        PreferencesGroupedForm {
            Section {
                PatronageAppSection(patronageService: patronageService)
            }

            Section(header: Text("preferences_section_general_settings_title".loco())) {
                LaunchAtLoginANDPreferredLanguagePicker()

                // 12/24-hour format affects every surface that renders clock
                // times (dropdown rows, timeline, event details, fullscreen
                // notification), so it lives with the app-wide options rather
                // than under Menu.
                Picker(
                    preferenceLabel("preferences_appearance_menu_time_format_title"),
                    selection: $timeFormat
                ) {
                    Text("preferences_appearance_menu_time_format_12_hour_value".loco())
                        .tag(TimeFormat.am_pm)
                    Text("preferences_appearance_menu_time_format_24_hour_value".loco())
                        .tag(TimeFormat.military)
                }
            }

            Section(header: Text("preferences_section_shortcuts_title".loco())) {
                ShortcutsSection()
            }
        }
    }
}

struct ShortcutsSection: View {
    var body: some View {
        ShortcutRow(
            title: "preferences_general_shortcut_open_menu".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .openMenuShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_join_next".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .joinEventShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_create_meeting".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_join_from_clipboard".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .openClipboardShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_toggle_meeting_name_visibility".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .toggleMeetingTitleVisibilityShortcut)
        )
    }
}

private struct ShortcutRow<Recorder: View>: View {
    let title: String
    let recorder: Recorder

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            recorder
        }
    }
}

struct PatronageAppSection: View {
    @EnvironmentObject var appModel: AppModel
    @Default(.patronageDuration) var patronageDuration
    @Default(.isInstalledFromAppStore) var isInstalledFromAppStore
    @ObservedObject var patronageService: PatronageService

    var body: some View {
        // The whole About card is one Form row (a single VStack) so the
        // grouped form doesn't insert its own separators between the identity,
        // support, and link clusters — we draw the one divider we want.
        VStack(alignment: .leading, spacing: 16) {
            if isInstalledFromAppStore {
                patronagePurchaseBlock
                Divider()
            }

            HStack(alignment: .top, spacing: 16) {
                Image("appIconForAbout")
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("MeetingBar")
                            .font(.title2).bold()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("preferences_general_meeting_bar_description".loco())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Divider()

            // Primary support actions, made prominent with icons.
            HStack(spacing: 10) {
                Button {
                    Links.patreon.openInDefaultBrowser()
                } label: {
                    Label("Patreon", systemImage: "heart.fill")
                }
                Button {
                    Links.buymeacoffee.openInDefaultBrowser()
                } label: {
                    Label("Buy Me A Coffee", systemImage: "cup.and.saucer.fill")
                }
                Spacer()
            }
            .buttonStyle(.bordered)
            .tint(.pink)

            // Secondary links + diagnostics, visually quieter.
            HStack(spacing: 16) {
                Button("GitHub") {
                    Links.github.openInDefaultBrowser()
                }
                .buttonStyle(.link)
                Button("preferences_general_external_contact".loco()) {
                    Links.emailMe.openInDefaultBrowser()
                }
                .buttonStyle(.link)
                Spacer()
                Button("preferences_status_copy_diagnostics".loco()) {
                    DiagnosticsClipboard.copy(
                        snapshot: DiagnosticsSnapshot(appState: appModel.state)
                    )
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var patronagePurchaseBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("preferences_general_patron_title".loco()).bold()
                Spacer()
                Text("preferences_general_patron_description".loco()).font(.system(size: 10))
            }
            HStack {
                Button(action: {
                    Task { await patronageService.purchase(PatronageProducts.threeMonth) }
                }) {
                    Text("preferences_general_patron_three_months".loco())
                }
                .disabled(
                    patronageService.isProcessing
                        || !patronageService.isProductAvailable(PatronageProducts.threeMonth)
                )
                Button(action: {
                    Task { await patronageService.purchase(PatronageProducts.sixMonth) }
                }) {
                    Text("preferences_general_patron_six_months".loco())
                }
                .disabled(
                    patronageService.isProcessing
                        || !patronageService.isProductAvailable(PatronageProducts.sixMonth)
                )
                Button(action: {
                    Task { await patronageService.purchase(PatronageProducts.twelveMonth) }
                }) {
                    Text("preferences_general_patron_twelve_months".loco())
                }
                .disabled(
                    patronageService.isProcessing
                        || !patronageService.isProductAvailable(PatronageProducts.twelveMonth)
                )
                Button(action: {
                    Task { await patronageService.restore() }
                }) {
                    Text("preferences_general_patron_restore_purchases".loco())
                }
                .disabled(patronageService.isProcessing)
            }
            if patronageDuration > 0 {
                Text("preferences_general_patron_thank_for_purchase".loco(patronageDuration))
            }
        }
    }
}

#Preview() {
    GeneralTab(patronageService: PatronageService())
        .padding()
        .frame(width: 700, height: 620)
}
