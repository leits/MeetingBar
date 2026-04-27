//
//  MeetingOpener.swift
//  MeetingBar
//

import AppKit
import Defaults

/// Opens a meeting for a given event:
///
/// 1. If a meeting link was detected — runs the user's join AppleScript hook
///    (when configured), then opens the URL with `openMeetingURL`.
/// 2. Otherwise falls back to the event's plain URL, opened in the default
///    browser.
/// 3. Otherwise shows the user a "link missing" notification.
///
/// Extracted from `MBEvent.openMeeting()` so opening behaviour is testable
/// in isolation and `MBEvent` moves toward a data-only struct.
enum MeetingOpener {
    static func open(event: MBEvent) {
        if let meetingLink = event.meetingLink {
            runJoinEventScriptIfConfigured()
            openMeetingURL(meetingLink.service, meetingLink.url, nil)
            return
        }

        if let eventUrl = event.url {
            eventUrl.openInDefaultBrowser()
            return
        }

        sendNotification(
            "status_bar_error_link_missed_title".loco(event.title),
            "status_bar_error_link_missed_message".loco()
        )
    }

    private static func runJoinEventScriptIfConfigured() {
        guard Defaults[.runJoinEventScript],
              let scriptLocation = Defaults[.joinEventScriptLocation]
        else { return }
        let scriptURL = scriptLocation.appendingPathComponent("joinEventScript.scpt")
        let task = try? NSUserAppleScriptTask(url: scriptURL)
        task?.execute { error in
            if let error {
                sendNotification(
                    "status_bar_error_apple_script_title".loco(),
                    error.localizedDescription
                )
            }
        }
    }
}
