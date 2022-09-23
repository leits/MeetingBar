//
//  Changelog.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 22.03.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults

struct ChangelogView: View {
    @Default(.lastRevisedVersionInChangelog) var lastRevisedVersionInChangelog

    var body: some View {
        VStack(alignment: .center, spacing: 15) {
            List {
                if compareVersions("3.2.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.2.0")) {
                        Text("• Added setting to only show events starting in x minutes")
                        Text("• Added Safari as a browser option")
                        Text("• Recognize meetings in outlook safe links")
                        Text("• New integrations: Discord, Jam, and Blackboard Collaborate")
                        Text("and small bug fixes")
                    }
                }
                if compareVersions("3.3.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.3.0")) {
                        Text("⏱️ Fixed bug with timer freeze")
                        Text("🧰 Browser management")
                        Text("⚡ Quick Actions: ")
                        Text("  - Show/hide meeting title in status bar")
                        Text("  - Open meeting from clipboard")
                        Text("• Customizable appereance for events without meeting links")
                        Text("• Localization")
                        Text("• Create meetings in Jam")
                        Text("• Open event in Fantastical from event submenu")
                        Text("• Integration with subscribed calendars")
                    }
                }
                if compareVersions("3.4.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.4.0")) {
                        Text("📋 New view of notes in the event submenu with selectable text and clickable links.")
                        Text("🧭 Fixed a bug with opening meetings in a new browser instance")
                        Text("and small bug fixes")
                    }
                }
                if compareVersions("3.5.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.5.0")) {
                        Text("🌍 Added translations into Croatian, German, French, and Norwegian Bokmål")
                        Text("All app notifications are now removed after all meetings are over")
                        Text("Improved RingCentral and Zoom links detection")
                        Text("and small bug fixes")
                    }
                }
                if compareVersions("3.6.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.6.0")) {
                        Text("🌍 Added translations into Czech")
                        Text("Added integration with Vowel")
                        Text("Fixed zoom link detection")
                    }
                }
                if compareVersions("3.7.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.7.0")) {
                        Text("🌍 Added translations into Japanese")
                        Text("🕑 Round the timer up, not down")
                        Text("⚡ Quick Actions in event submenu: ")
                        Text("  - Email attendees")
                        Text("  - Copy meeting link")
                    }
                }
                if compareVersions("3.8.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.8.0")) {
                        Text("🇵🇱 Added translations into Polish")
                        Text("• Support MeetInOne for Google Meet links")
                        Text("• Support Jitsi native app for Jitsi links")
                        Text("• Open the link from the event link field if the meeting service is not recognized")
                    }
                }
                if compareVersions("3.9.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.9.0")) {
                        Text("🌍 Added translations into Hebrew")
                        Text("• Advanced feature to filter out events by regex")
                        Text("• Added integration with Zhumu/WeMeeting, Lark, and Feishu")
                        Text("and small bug fixes")
                    }
                }
                if compareVersions("3.10.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 3.10.0")) {
                        Text("⚡ New \"Refresh source\" Quick Action")
                        Text("🌍 Translation into Turkish")
                        Text("• Integrations with Facetime, Vimeo Showcases, and oVice")
                    }
                }
                if compareVersions("4.0.0", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 4.0")) {
                        Text("⚡⚡⚡ Direct integration with Google Calendar ⚡⚡⚡")
                        Text("😴 Notification snooze")
                        Text("🌍 Translation into Italian")
                        Text("• Advanced feature to run AppleScript on event start")
                        Text("• Advanced feature to join events automatically")
                        Text("• Integration with Pop, Livestorm, Chorus & Gong")
                        Text("• Fixed readability of the statusbar text in multi-screen setups")
                        Text("• Fixed crash due to null emails for event attendees")
                    }
                }

                if compareVersions("4.0.7", lastRevisedVersionInChangelog) {
                    Section(header: Text("Version 4.0.7")) {
                        Text("Fix notification warning from overlapping with notification settings")
                    }
                }
            }.listStyle(SidebarListStyle())
            Button("general_close".loco(), action: close)
        }.padding()
    }

    func close() {
        NSApplication.shared.keyWindow?.close()
    }
}
