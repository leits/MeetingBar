//
//  MeetingOpeningPolicy.swift
//  MeetingBar
//

import Foundation

struct MeetingOpeningEvent: Equatable {
    let title: String
    let meetingLink: MeetingLink?
    let eventURL: URL?
}

enum MeetingOpeningAction: Equatable {
    case openMeetingLink(MeetingLink, runJoinScript: Bool)
    case openEventURL(URL)
    case notifyMissingLink(title: String)
}

enum MeetingOpeningPolicy {
    static func action(
        for event: MeetingOpeningEvent,
        runJoinEventScript: Bool
    ) -> MeetingOpeningAction {
        if let meetingLink = event.meetingLink {
            return .openMeetingLink(meetingLink, runJoinScript: runJoinEventScript)
        }

        if let eventURL = event.eventURL {
            return .openEventURL(eventURL)
        }

        return .notifyMissingLink(title: event.title)
    }
}
