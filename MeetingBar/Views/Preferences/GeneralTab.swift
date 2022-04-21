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
    @Default(.launchAtLogin) var launchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Section {
                Spacer()
                LaunchAtLoginANDPreferredLanguagePicker()
                Divider()
                JoinEventNotificationPicker()
                AutomaticEventJoinPicker()
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
    @State var showingPatronageModal = false
    @State var showingContactModal = false

    @Default(.isInstalledFromAppStore) var isInstalledFromAppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .center) {
                Spacer()
                HStack {
                    VStack(alignment: .center) {
                        Image(nsImage: NSImage(named: "appIconForAbout")!).resizable().frame(width: 120.0, height: 120.0)
                        Text("MeetingBar").font(.system(size: 20)).bold()
                        if Bundle.main.infoDictionary != nil {
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")").foregroundColor(.gray)
                        }
                    }.lineLimit(1).minimumScaleFactor(0.5).frame(minWidth: 0, maxWidth: .infinity)
                    VStack {
                        Spacer()
                        Text("preferences_general_meeting_bar_description".loco()).multilineTextAlignment(.center)
                        Spacer()

                        HStack {
                            Spacer()
                            Button(action: clickPatronage) {
                                Text("preferences_general_external_patronage".loco())
                            }.sheet(isPresented: $showingPatronageModal) {
                                PatronageModal()
                            }
                            Spacer()
                            Button(action: { Links.github.openInDefaultBrowser() }) {
                                Text("preferences_general_external_gitHub".loco())
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
                Spacer()
            }
        }
    }

    func clickPatronage() {
        if isInstalledFromAppStore {
            showingPatronageModal.toggle()
        } else {
            Links.patreon.openInDefaultBrowser()
        }
    }
}

struct PatronageModal: View {
    @Environment(\.presentationMode) var presentationMode
    @State var products: [String] = []

    @Default(.patronageDuration) var patronageDuration

    var body: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("preferences_general_patron_title".loco()).bold()
                    }
                }.frame(width: 120)
                Spacer()
                VStack(alignment: .leading) {
                    Button(action: { purchasePatronage(patronageProducts.threeMonth) }) {
                        Text("preferences_general_patron_three_months".loco()).frame(width: 150)
                    }
                    Button(action: { purchasePatronage(patronageProducts.sixMonth) }) {
                        Text("preferences_general_patron_six_months".loco()).frame(width: 150)
                    }
                    Button(action: { purchasePatronage(patronageProducts.twelveMonth) }) {
                        Text("preferences_general_patron_twelve_months".loco()).frame(width: 150)
                    }
                    Text("preferences_general_patron_description".loco()).font(.system(size: 10))
                }.frame(maxWidth: .infinity)
            }
            if patronageDuration > 0 {
                Divider()
                Spacer()
                Text("preferences_general_patron_thank_for_purchase".loco(patronageDuration))
            }
            Spacer()
            Divider()
            HStack {
                Button(action: restorePatronagePurchases) {
                    Text("preferences_general_patron_restore_purchases".loco())
                }
                Spacer()
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("general_close".loco())
                }
            }
        }.padding().frame(width: 400, height: 300)
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
                Text("preferences_general_feedback_twitter".loco()).frame(width: 80)
            }
            Button(action: { Links.telegram.openInDefaultBrowser() }) {
                Text("preferences_general_feedback_telegram".loco()).frame(width: 80)
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
