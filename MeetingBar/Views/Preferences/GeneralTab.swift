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

    func openAboutThisApp() {
        NSLog("Open AboutThisApp")
        _ = openLinkInDefaultBrowser(Links.aboutThisApp)
    }

    func openSupportTheCreator() {
        NSLog("Open SupportTheCreator")
        _ = openLinkInDefaultBrowser(Links.supportTheCreator)
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
                        Image(nsImage: NSImage(named: NSImage.touchBarGetInfoTemplateName)!).resizable().frame(width: 12.0, height: 16.0)
                        Text("About this app")
                    }.sheet(isPresented: $showingAboutModal) {
                        AboutModal()
                    }
                    Spacer()
                    Button(action: openManual) {
                        Image(nsImage: NSImage(named: NSImage.followLinkFreestandingTemplateName)!)
                        Text("Open manual")
                    }
                }
            }
        }
    }

    func openAboutThisApp() {
        NSLog("Open AboutThisApp")
        _ = openLinkInDefaultBrowser(Links.aboutThisApp)
    }

    func openManual() {
        NSLog("Open manual")
        _ = openLinkInDefaultBrowser(Links.manual)
    }
}


struct AboutModal: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading) {
                Text(
                    ""
                )
            }
            Spacer()
            HStack {
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Close")
                }
            }
        }.padding().frame(width: 400, height: 200)
    }
}
