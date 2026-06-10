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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("preferences_section_general_settings_title".loco(), systemImage: "gearshape")) {
                LaunchAtLoginANDPreferredLanguagePicker()
                    .padding(10)
            }
            .padding(.bottom, 4)

            GroupBox(label: Label("preferences_section_shortcuts_title".loco(), systemImage: "keyboard")) {
                ShortcutsSection()
                    .padding(10)
            }
            .padding(.bottom, 4)

            GroupBox(label: Label("preferences_section_about_title".loco(), systemImage: "person.crop.circle")) {
                PatronageAppSection(patronageService: patronageService)
                    .padding(10)
            }
            .padding(.bottom, 4)

            Spacer()
        }
    }
}

struct ShortcutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
}

private struct ShortcutRow<Recorder: View>: View {
    let title: String
    let recorder: Recorder

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            recorder
        }
        .padding(.vertical, 2)
    }
}


struct PatronageAppSection: View {
    @EnvironmentObject var appModel: AppModel
    @Default(.patronageDuration) var patronageDuration
    @Default(.isInstalledFromAppStore) var isInstalledFromAppStore
    @ObservedObject var patronageService: PatronageService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isInstalledFromAppStore {
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
                Divider()
            }

            HStack(alignment: .center, spacing: 16) {
                Image("appIconForAbout")
                    .resizable()
                    .frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MeetingBar")
                        .font(.title2).bold()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("preferences_general_meeting_bar_description".loco())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("Patreon") {
                    Links.patreon.openInDefaultBrowser()
                }
                Button("Buy Me A Coffee") {
                    Links.buymeacoffee.openInDefaultBrowser()
                }
                Button("GitHub") {
                    Links.github.openInDefaultBrowser()
                }
                Button("preferences_general_external_contact".loco()) {
                    Links.emailMe.openInDefaultBrowser()
                }
                Spacer()
                Button("preferences_status_copy_diagnostics".loco()) {
                    DiagnosticsClipboard.copy(
                        snapshot: DiagnosticsSnapshot(appState: appModel.state)
                    )
                }
            }
            .controlSize(.small)
        }
    }
}


#Preview() {
    GeneralTab(patronageService: PatronageService())
        .padding()
        .frame(width: 700, height: 620)
}
