//
//  MeetingOpener.swift
//  MeetingBar
//

import AppKit
import Defaults

protocol MeetingOpeningPerforming {
    func runJoinEventScriptIfConfigured()
    func openMeetingLink(_ service: MeetingServices?, _ url: URL)
    func openEventURL(_ url: URL)
    func notifyMissingLink(title: String)
}

struct SystemMeetingOpeningPerformer: MeetingOpeningPerforming {
    func runJoinEventScriptIfConfigured() {
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

    func openMeetingLink(_ service: MeetingServices?, _ url: URL) {
        openMeetingURL(service, url, nil)
    }

    func openEventURL(_ url: URL) {
        url.openInDefaultBrowser()
    }

    func notifyMissingLink(title: String) {
        sendNotification(
            "status_bar_error_link_missed_title".loco(title),
            "status_bar_error_link_missed_message".loco()
        )
    }
}

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
    static func open(
        event: MBEvent,
        performer: any MeetingOpeningPerforming = SystemMeetingOpeningPerformer()
    ) {
        let action = MeetingOpeningPolicy.action(
            for: MeetingOpeningEvent(
                title: event.title,
                meetingLink: event.meetingLink,
                eventURL: event.url
            ),
            runJoinEventScript: Defaults[.runJoinEventScript]
        )

        perform(action, performer: performer)
    }

    static func open(
        meetingLink: MeetingLink,
        performer: any MeetingOpeningPerforming = SystemMeetingOpeningPerformer()
    ) {
        perform(
            .openMeetingLink(meetingLink, runJoinScript: Defaults[.runJoinEventScript]),
            performer: performer
        )
    }

    static func perform(_ action: MeetingOpeningAction, performer: any MeetingOpeningPerforming) {
        switch action {
        case let .openMeetingLink(meetingLink, runJoinScript):
            if runJoinScript {
                performer.runJoinEventScriptIfConfigured()
            }
            performer.openMeetingLink(meetingLink.service, meetingLink.url)
        case let .openEventURL(eventURL):
            performer.openEventURL(eventURL)
        case let .notifyMissingLink(title):
            performer.notifyMissingLink(title: title)
        }
    }
}
