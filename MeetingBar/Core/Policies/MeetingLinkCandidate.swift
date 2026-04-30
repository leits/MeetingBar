//
//  MeetingLinkCandidate.swift
//  MeetingBar
//

import Foundation

/// Where a meeting link candidate was extracted from. Higher-priority sources
/// are preferred when more than one candidate is found for an event.
///
/// Used by `MeetingLinkCandidatePolicy.best(from:)` and `ranked(from:)`.
/// The integration with `MBEvent` (Phase 3 PR-B) will collect candidates
/// from each available source and pass the list to this policy.
enum MeetingLinkSource: Equatable {
    /// Structured conference data exposed by the provider — e.g. Google
    /// Calendar's `conferenceData.entryPoints[type=video]`. Highest priority
    /// because the provider has explicitly tagged this URL as the meeting.
    case providerConferenceData

    /// The event's explicit `url` field (EventKit `EKEvent.url`, Google
    /// Calendar `event.hangoutLink` style fields surfaced as a URL).
    case eventURL

    /// The event's location field — sometimes hosts paste the meeting URL
    /// here when there is no structured conference data.
    case location

    /// Free-text notes / description.
    case notes

    /// Notes field after HTML tag / entity stripping. Lower priority than
    /// raw `notes` because stripping can occasionally normalise legitimate
    /// links into a less canonical form.
    case strippedHTMLNotes

    /// User-provided regex match. Last-resort fallback so a custom regex
    /// cannot override a real provider conference URL.
    case customRegex

    /// Numeric priority — larger wins. Gaps allow inserting new sources
    /// later without renumbering existing ones.
    var priority: Int {
        switch self {
        case .providerConferenceData: return 60
        case .eventURL: return 50
        case .location: return 40
        case .notes: return 30
        case .strippedHTMLNotes: return 20
        case .customRegex: return 10
        }
    }
}

/// A single meeting-link candidate extracted from one source field of an event.
/// Multiple candidates per event are collected in Phase 3 PR-B and ranked here.
struct MeetingLinkCandidate: Equatable {
    let url: URL
    let service: MeetingServices?
    let source: MeetingLinkSource
}

enum MeetingLinkCandidatePolicy {
    /// Picks the best candidate for an event:
    ///
    /// 1. by source priority — provider conference data beats notes;
    /// 2. within the same source, the longer URL wins so a Zoom link that
    ///    carries a password/token suffix beats a truncated form of the
    ///    same URL found in another source slot.
    static func best(from candidates: [MeetingLinkCandidate]) -> MeetingLinkCandidate? {
        candidates.max { lhs, rhs in
            if lhs.source.priority != rhs.source.priority {
                return lhs.source.priority < rhs.source.priority
            }
            return lhs.url.absoluteString.count < rhs.url.absoluteString.count
        }
    }

    /// Returns candidates ranked best-to-worst, deduplicated by URL string.
    /// Useful for a future "open with another link" menu without re-running
    /// detection.
    static func ranked(from candidates: [MeetingLinkCandidate]) -> [MeetingLinkCandidate] {
        let unique = Dictionary(grouping: candidates, by: { $0.url.absoluteString })
            .compactMapValues(\.first)
            .values
        return Array(unique).sorted { lhs, rhs in
            if lhs.source.priority != rhs.source.priority {
                return lhs.source.priority > rhs.source.priority
            }
            return lhs.url.absoluteString.count > rhs.url.absoluteString.count
        }
    }
}
