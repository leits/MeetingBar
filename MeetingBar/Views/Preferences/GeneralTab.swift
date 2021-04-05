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
            Spacer()
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            Divider()
            Section {
                JoinEventNotificationPicker()
            }
            Divider()
            ShortcutsSection()
            Spacer()
            Divider()
            PatronageAppSection()
        }.padding()
    }
}

struct ShortcutsSection: View {
    var body: some View {
        HStack {
            Text("Shortcuts").font(.headline).bold()
            Spacer()
            VStack {
                Text("Open menu:")
                KeyboardShortcuts.Recorder(for: .openMenuShortcut)
            }
            VStack {
                Text("Create meeting:")
                KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
            }
            VStack {
                Text("Join next event meeting:")
                KeyboardShortcuts.Recorder(for: .joinEventShortcut)
            }
            VStack {
                Text("Join meeting from clipbloard:")
                KeyboardShortcuts.Recorder(for: .openClipboardShortcut)
            }
        }
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
                        Text("MeetingBar is open-source app created by Andrii Leitsius\nThe app aims to make your experience with online meetings smoother and easier").multilineTextAlignment(.center)
                        Spacer()

                        HStack {
                            Spacer()
                            Button(action: clickPatronage) {
                                Text("Patronage")
                            }.sheet(isPresented: $showingPatronageModal) {
                                PatronageModal()
                            }
                            Spacer()
                            Button(action: { Links.github.openInDefaultBrowser() }) {
                                Text("GitHub")
                            }
                            Spacer()
                            Button(action: { self.showingContactModal.toggle() }) {
                                Text("Contact")
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
            self.showingPatronageModal.toggle()
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
                        Text("Become a Patron").bold()
                    }
                }.frame(width: 120)
                Spacer()
                VStack(alignment: .leading) {
                    Button(action: { purchasePatronage(patronageProducts.threeMonth) }) {
                        Text("3 Month - 2.99 USD").frame(width: 150)
                    }
                    Button(action: { purchasePatronage(patronageProducts.sixMonth) }) {
                        Text("6 Month - 5.99 USD").frame(width: 150)
                    }
                    Button(action: { purchasePatronage(patronageProducts.twelveMonth) }) {
                        Text("12 Month - 11.99 USD").frame(width: 150)
                    }
                    Text("These one-time purchases do not auto-renew.").font(.system(size: 10))
                }.frame(maxWidth: .infinity)
            }
            if patronageDuration > 0 {
                Divider()
                Spacer()
                Text("Thanks! You support MeetingBar for \(patronageDuration) Month! 🎉")
            }
            Spacer()
            Divider()
            HStack {
                Button(action: restorePatronagePurchases) {
                    Text("Restore Purchases")
                }
                Spacer()
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Close")
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
            Text("If you have any questions or feedback,\nfeel free to contact me:")
            Spacer()

            Button(action: { Links.emailMe.openInDefaultBrowser() }) {
                Text("email").frame(width: 80)
            }
            Button(action: { Links.twitter.openInDefaultBrowser() }) {
                Text("twitter").frame(width: 80)
            }
            Button(action: { Links.telegram.openInDefaultBrowser() }) {
                Text("telegram").frame(width: 80)
            }
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Close")
                }
            }
        }.padding().frame(width: 300, height: 220)
    }
}
