//
//  URLHandler.swift
//  MeetingBar
//

import Foundation

/// Handles `meetingbar://` custom URL scheme events and OAuth callback URLs.
///
/// Owned by `AppDelegate`; decouples URL dispatch logic from the app delegate.
@MainActor
final class URLHandler {
    var onOpenPreferences: () -> Void = {}
    var onOAuthCallback: (URL) -> Void = { _ in }

    func handle(url: URL) {
        if url == URL(string: "meetingbar://preferences") {
            onOpenPreferences()
        } else {
            onOAuthCallback(url)
        }
    }
}
