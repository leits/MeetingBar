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
                Group {
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
                }
                Group {
                    if compareVersions("4.1.0", lastRevisedVersionInChangelog) {
                        Section(header: Text("Version 4.1")) {
                            Text("• Integrations with Preply, Demodesk, Teemyco, UserZoom, Venue, and Zoho Cliq")
                            Text("• Improved meetings recognition in the event description with html links")
                            Text("• Fixed autojoin for meetings without a link")
                            Text("• Fixed not showing the next meeting in the status bar if it starts the next day for a two-day view")
                            Text("• Fixed padding for all-day meetings in the menu with am/pm end time enabled.")
                        }
                    }
                    if compareVersions("4.2.0", lastRevisedVersionInChangelog) {
                        Section(header: Text("Version 4.2")) {
                            Text("⚡ Quick Action for dismissing current/next event ⚡ ")
                            Text("• Added option to use any browser for Zoom, Teams, and Jitsi meetings")
                            Text("• Improved Zoom & UserZoom links recognition")
                            Text("• Performance optimisations")
                            Text("• Fixed Google re-login on every app restart for Google Calendar API data source")
                            Text("• Fixed delegated calendar for macOS Calendar data source")
                        }
                    }
                    if compareVersions("4.3.0", lastRevisedVersionInChangelog) {
                        Section(header: Text("Version 4.3")) {
                            Text("• Event notifications are now Time-Sensitive and can break through Focus mode so you don't miss your meetings (can be changed in notification settings)")
                                .lineLimit(nil)
                            Text("• Added link recognition for Slack Huddle, Reclaim.ai, Vimeo Venues, Gather")
                            Text("• Fixed Launch at login and many other small bugs")
                        }
                    }
                    if compareVersions("4.4.0", lastRevisedVersionInChangelog) {
                        Section(header: Text("Version 4.4")) {
                            Text("⚙️ Integration with the Shortcuts app!\n\nYou can automate your flows with \"Join Nearest Meeting\" and \"Get Nearest Event Details\" actions.").lineLimit(nil)
                        }
                    }
                    if compareVersions("4.5.0", lastRevisedVersionInChangelog) {
                        Section(header: Text("Version 4.5")) {
                            Text("• Improved links recognition for Microsoft Teams and Zoom Webinar")
                            Text("• Improved performance on actions")
                            Text("• Optimized direct Google Calendar integration")
                            Text("• Updated Slack huddle icon to properly scale within a menu")
                        }
                    }
                    if compareVersions("4.6.0", lastRevisedVersionInChangelog) {
                        Section(header: Text("Version 4.6")) {
                            Text("• Configure appearance for tentative events")
                            Text("• Open Slack huddle links directly in Slack app")
                            Text("• Open preferences with `meetingbar://preferences` link")
                            Text("• Dismiss event action for Shortcuts")
                            Text("• Fixed a bug with autojoin when the screen is locked")
                        }
                    }
                    if compareVersions("4.7.0", lastRevisedVersionInChangelog) {
                        Section(header: Text("Version 4.7")) {
                            Text("• Autojoin is now semi-automatic with a full-screen notification")
                            Text("• Integrations with Pumble, Suit Conference, Doxy.me")
                            Text("• Improved Zoom link recognition")
                            Text("• Fixed high CPU usage when meeting details are displayed in the submenu")
                        }
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
