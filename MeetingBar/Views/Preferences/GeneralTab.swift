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
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Section {
                LaunchAtLoginANDPreferredLanguagePicker()
                Divider()
                JoinEventNotificationPicker()
                FullscreenNotificationPicker()
                Divider()
            }
            Section {
                ShortcutsSection()
                Divider()
                PatronageAppSection()
            }
        }.padding()
    }
}

struct ShortcutsSection: View {
    @State var showingModal = false

    var body: some View {
        HStack {
            Text("preferences_general_shortcut_create_meeting".loco())
            KeyboardShortcuts.Recorder(for: .createMeetingShortcut)

            Text("preferences_general_shortcut_join_next".loco())
            KeyboardShortcuts.Recorder(for: .joinEventShortcut)

            Spacer()

            Button(action: { self.showingModal.toggle() }) {
                Text("preferences_general_all_shortcut".loco())
            }.sheet(isPresented: $showingModal) {
                ShortcutsModal()
            }
        }
    }
}

struct ShortcutsModal: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Text("preferences_general_option_shortcuts".loco()).font(.headline).bold()
            List {
                HStack {
                    Text("preferences_general_shortcut_open_menu".loco())
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .openMenuShortcut)
                }
                HStack {
                    Text("preferences_general_shortcut_create_meeting".loco())
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
                }
                HStack {
                    Text("preferences_general_shortcut_join_next".loco())
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                }
                HStack {
                    Text("preferences_general_shortcut_join_from_clipboard".loco())
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .openClipboardShortcut)
                }
                HStack {
                    Text("preferences_general_shortcut_toggle_meeting_name_visibility".loco())
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleMeetingTitleVisibilityShortcut)
                }
            }
            HStack {
                Spacer()
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("general_close".loco())
                }
            }
        }.padding().frame(width: 420, height: 300)
    }
}

struct PatronageAppSection: View {
    @State var showingContactModal = false
    @Default(.patronageDuration) var patronageDuration
    @Default(.isInstalledFromAppStore) var isInstalledFromAppStore

    var body: some View {
        VStack(alignment: .center, spacing: 15) {
            if isInstalledFromAppStore {
                HStack {
                    Text("preferences_general_patron_title".loco()).bold()
                    Spacer()
                    Text("preferences_general_patron_description".loco()).font(.system(size: 10))
                }
                HStack {
                    Button(action: { purchasePatronage(PatronageProducts.threeMonth) }) {
                        Text("preferences_general_patron_three_months".loco())
                    }
                    Button(action: { purchasePatronage(PatronageProducts.sixMonth) }) {
                        Text("preferences_general_patron_six_months".loco())
                    }
                    Button(action: { purchasePatronage(PatronageProducts.twelveMonth) }) {
                        Text("preferences_general_patron_twelve_months".loco())
                    }
//                    Button(action: restorePatronagePurchases) {
//                        Text("preferences_general_patron_restore_purchases".loco())
//                    }
                }
                if patronageDuration > 0 {
                    Text("preferences_general_patron_thank_for_purchase".loco(patronageDuration))
                }
                Divider()
            }

            HStack {
                VStack(alignment: .center) {
                    Image("appIconForAbout").resizable().frame(width: 120.0, height: 120.0)
                    Text("MeetingBar").font(.system(size: 20)).bold()
                    Text(Defaults[.appVersion]).foregroundColor(.gray)
                }.lineLimit(1).minimumScaleFactor(0.5).frame(minWidth: 0, maxWidth: .infinity)
                VStack {
                    Spacer()
                    Text("preferences_general_meeting_bar_description".loco()).multilineTextAlignment(.center)
                    Text("")
                    HStack {
                        Spacer()
                        Button(action: { Links.patreon.openInDefaultBrowser() }) {
                            Text("Patreon")
                        }
                        Spacer()
                        Button(action: { Links.buymeacoffee.openInDefaultBrowser() }) {
                            Text("Buy Me A Coffee")
                        }
                        Spacer()
                        Button(action: { Links.github.openInDefaultBrowser() }) {
                            Text("GitHub")
                        }
                        Spacer()
                        Button(action: { self.showingContactModal.toggle() }) {
                            Text("preferences_general_external_contact".loco())
                        }.sheet(isPresented: $showingContactModal) {
                            ContactModal()
                        }
                        Spacer()
                    }
                    Spacer()
                }.frame(minWidth: 360, maxWidth: .infinity)
            }
        }
    }
}

struct ContactModal: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Spacer()
            Text("preferences_general_feedback_title".loco())
            Spacer()

            Button(action: { Links.emailMe.openInDefaultBrowser() }) {
                Text("preferences_general_feedback_email".loco()).frame(width: 80)
            }
            Button(action: { Links.twitter.openInDefaultBrowser() }) {
                Text("Twitter").frame(width: 80)
            }
            Button(action: { Links.telegram.openInDefaultBrowser() }) {
                Text("Telegram").frame(width: 80)
            }
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("general_close".loco())
                }
            }
        }.padding().frame(width: 300, height: 220)
    }
}
