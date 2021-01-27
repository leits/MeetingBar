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
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .center) {
                Spacer()
                Text("MeetingBar").font(.system(size: 20)).bold()
                if Bundle.main.infoDictionary != nil {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")").foregroundColor(.gray)
                }
                Spacer()
                HStack {
                    Button("About this app", action: openAboutThisApp)
                    Spacer()
                    Button("Open manual", action: openManual)
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
