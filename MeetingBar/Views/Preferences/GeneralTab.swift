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
            AboutAppSection()
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
        }
    }
}

struct AboutAppSection: View {
    @State var showingAboutModal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .center) {
                Spacer()
                VStack(alignment: .center) {
                    Image(nsImage: NSImage(named: EventTitleIconFormat.appicon.rawValue)!).resizable()
                            .frame(width: 120.0, height: 120.0)
                    Text("MeetingBar").font(.system(size: 20)).bold()
                    if Bundle.main.infoDictionary != nil {
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")").foregroundColor(.gray)
                    }
                }
                Spacer()
                HStack {
                    Button(action: { self.showingAboutModal.toggle() }) {
                        Text("About")
                    }.sheet(isPresented: $showingAboutModal) {
                        AboutModal()
                    }
                    Spacer()
//                    Button(action: openManual) {
//                        Text("Manual")
//                        Image(nsImage: NSImage(named: NSImage.followLinkFreestandingTemplateName)!)
//                    }
                }
            }
        }
    }

    func openManual() {
        NSLog("Open manual")
        Links.manual.openInDefaultBrowser()
    }
}


struct AboutModal: View {
    @Environment(\.presentationMode) var presentationMode
    @State var products: [String] = []

    @Default(.patronageDuration) var patronageDuration
    @Default(.isInstalledFromAppStore) var isInstalledFromAppStore

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading) {
                Text("MeetingBar is open-source app created by Andrii Leitsius. The app aims to make your experience with online meetings smoother and easier.")
            }
            Divider()
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Become a Patron").bold()
                    }
                }.frame(width: 120)
                Spacer()
                VStack(alignment: .leading) {
                    if isInstalledFromAppStore {
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
                    } else {
                        Button(action: self.supportOnPatreon) {
                            Text("on Patreon").frame(width: 150)
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
            Divider()
            Spacer()
            if isInstalledFromAppStore, patronageDuration > 0 {
                Text("Thanks! You support MeetingBar for \(patronageDuration) Month! 🎉")
                Spacer()
                Divider()
            }
            HStack {
                if isInstalledFromAppStore {
                    Button(action: restorePatronagePurchases) {
                        Text("Restore Purchases")
                    }
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

    func supportOnPatreon() {
        NSLog("Click supportOnPatreon")
        Links.patreon.openInDefaultBrowser()
    }
}
