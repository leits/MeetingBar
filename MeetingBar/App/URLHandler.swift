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
    func route(for url: URL) -> AppRoute {
        guard url.scheme == "meetingbar" else {
            return .oauthCallback(url)
        }

        if url.host == "preferences" {
            return .preferences
        }

        return .unknown(url)
    }
}
