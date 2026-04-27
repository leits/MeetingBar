//
//  MeetingLinkDetector.swift
//  MeetingBar
//

import Foundation

/// Picks the best meeting link from an event's text fields.
///
/// Field order matches historical behavior:
/// `location` → `eventURL` → `notes` → `notes` with HTML tags stripped.
/// First match wins. Google Meet URLs are post-processed with an `authuser`
/// query parameter when an account email is available.
enum MeetingLinkDetector {
    static func detect(
        location: String?,
        eventURL: URL?,
        notes: String?,
        calendarEmail: String?,
        currentUserEmail: String?
    ) -> MeetingLink? {
        let candidateFields: [String?] = [
            location,
            eventURL?.absoluteString,
            notes,
            notes?.htmlTagsStripped()
        ]

        for field in candidateFields {
            guard let field, var detected = detectMeetingLink(field) else { continue }
            applyMeetAuthuserIfNeeded(
                link: &detected,
                calendarEmail: calendarEmail,
                currentUserEmail: currentUserEmail
            )
            return detected
        }
        return nil
    }

    private static func applyMeetAuthuserIfNeeded(
        link: inout MeetingLink,
        calendarEmail: String?,
        currentUserEmail: String?
    ) {
        guard link.service == .meet,
              let authAccount = calendarEmail ?? currentUserEmail,
              let encoded = authAccount.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let urlWithAuth = URL(string: link.url.absoluteString + "?authuser=\(encoded)")
        else { return }
        link.url = urlWithAuth
    }
}
