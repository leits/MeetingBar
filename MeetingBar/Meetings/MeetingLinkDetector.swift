//
//  MeetingLinkDetector.swift
//  MeetingBar
//
//  Owns everything related to extracting a meeting URL from an event:
//  the public `MeetingLink` value type, regex catalogue compiled from
//  `MeetingProvider.all`, helper functions for cleaning Outlook SafeLinks
//  and stripping HTML notes, the candidate ranking policy, and the
//  detector that orchestrates them.
//

import AppKit
import Foundation

// MARK: - Public value types

/// Catalogue of meeting service identifiers used as the primary key for
/// detection regexes, icons, browser preferences, and bookmarks. Provider
/// metadata (regex, icon, native-app browser) lives on `MeetingProvider.all`.
enum MeetingServices: String, Codable, CaseIterable, Sendable {
    case phone = "Phone"
    case meet = "Google Meet"
    case protonMeet = "Proton Meet"
    case hangouts = "Google Hangouts"
    case zoom = "Zoom"
    case zoom_native = "Zoom native"
    case teams = "Microsoft Teams"
    case webex = "Cisco Webex"
    case jitsi = "Jitsi"
    case chime = "Amazon Chime"
    case ringcentral = "Ring Central"
    case gotomeeting = "GoToMeeting"
    case gotowebinar = "GoToWebinar"
    case bluejeans = "BlueJeans"
    case eight_x_eight = "8x8"
    case demio = "Demio"
    case join_me = "Join.me"
    case zoomgov = "ZoomGov"
    case whereby = "Whereby"
    case uberconference = "Uber Conference"
    case blizz = "Blizz"
    case teamviewer_meeting = "Teamviewer Meeting"
    case vsee = "VSee"
    case starleaf = "StarLeaf"
    case duo = "Google Duo"
    case voov = "Tencent VooV"
    case facebook_workspace = "Facebook Workspace"
    case lifesize = "Lifesize"
    case skype = "Skype"
    case skype4biz = "Skype For Business"
    case skype4biz_selfhosted = "Skype For Business (SH)"
    case facetime = "Facetime"
    case pop = "Pop"
    case chorus = "Chorus"
    case gong = "Gong"
    case livestorm = "Livestorm"
    case facetimeaudio = "Facetime Audio"
    case youtube = "YouTube"
    case vonageMeetings = "Vonage Meetings"
    case meetStream = "Google Meet Stream"
    case around = "Around"
    case jam = "Jam"
    case discord = "Discord"
    case blackboard_collab = "Blackboard Collaborate"
    case url = "Any Link"
    case coscreen = "CoScreen"
    case vowel = "Vowel"
    case zhumu = "Zhumu"
    case lark = "Lark"
    case feishu = "Feishu"
    case vimeo = "Vimeo"
    case ovice = "oVice"
    case luma = "Luma"
    case preply = "Preply"
    case userzoom = "UserZoom"
    case venue = "Venue"
    case teemyco = "Teemyco"
    case demodesk = "Demodesk"
    case zoho_cliq = "Zoho Cliq"
    case slack = "Slack"
    case gather = "Gather"
    case reclaim = "Reclaim.ai"
    case tuple = "Tuple"
    case pumble = "Pumble"
    case suitConference = "Suit Conference"
    case doxyMe = "Doxy.me"
    case calcom = "Cal Video"
    case zmPage = "zm.page"
    case livekit = "LiveKit Meet"
    case meetecho = "Meetecho"
    case streamyard = "StreamYard"
    case riverside = "Riverside"
    case other = "Other"
}

public struct MeetingLink: Hashable, Equatable, Sendable {
    let service: MeetingServices?
    var url: URL
}

/// Where a meeting link candidate was extracted from. Higher-priority sources
/// are preferred when more than one candidate is found for an event.
enum MeetingLinkSource: Hashable, Sendable {
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
struct MeetingLinkCandidate: Hashable, Sendable {
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
    /// Useful for a "open with another link" menu without re-running detection.
    static func ranked(from candidates: [MeetingLinkCandidate]) -> [MeetingLinkCandidate] {
        let unique = Dictionary(grouping: candidates, by: { $0.url.absoluteString })
            .compactMapValues { best(from: $0) }
            .values
        return Array(unique).sorted { lhs, rhs in
            if lhs.source.priority != rhs.source.priority {
                return lhs.source.priority > rhs.source.priority
            }
            return lhs.url.absoluteString.count > rhs.url.absoluteString.count
        }
    }
}

// MARK: - Regex catalogue and text helpers

private let meetingLinkRegexes: [MeetingServices: NSRegularExpression] =
    MeetingProvider.regexPatterns.compactMapValues { pattern in
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            assertionFailure("Invalid built-in meeting link regex: \(pattern)")
            return nil
        }
    }

private let outlookSafeLinkRegex = try? NSRegularExpression(
    pattern: #"https://[\S]+\.safelinks\.protection\.outlook\.com/[\S]+url=([\S]*)"#)

func regex(for service: MeetingServices) -> NSRegularExpression? {
    meetingLinkRegexes[service]
}

func detectMeetingLink(_ rawText: String, customRegexes: [String] = []) -> MeetingLink? {
    let text = cleanupOutlookSafeLinks(rawText: rawText)

    for pattern in customRegexes {
        if let regex = try? NSRegularExpression(pattern: pattern),
            let link = getMatch(text: text, regex: regex),
            let url = URL(string: link) {
            return MeetingLink(service: MeetingServices.other, url: url)
        }
    }

    if text.contains("://") {
        for (svc, regex) in meetingLinkRegexes {
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let range = Range(match.range, in: text),
                let url = URL(string: String(text[range])) {
                return MeetingLink(service: svc, url: url)
            }
        }
    }
    return nil
}

/// Rewrites Outlook SafeLink wrappers in `rawText` back to their real
/// targets, so meeting-link detection sees the underlying URL rather than the
/// `…safelinks.protection.outlook.com/…url=<encoded>` redirect. Each pass
/// unwraps the first SafeLink and re-scans, which also resolves SafeLinks
/// nested inside one another.
///
/// The loop is deliberately bounded and only continues while it makes forward
/// progress. It stops when:
///
/// 1. the `url=` value can't be percent-decoded — a malformed or truncated
///    `%` escape, which `removingPercentEncoding` reports as `nil`;
/// 2. a rewrite leaves the text unchanged, so the same match would be found
///    again; or
/// 3. a hard pass cap is reached, as a final backstop.
///
/// Without these guards a single event carrying a malformed SafeLink would
/// loop forever and wedge calendar sync.
func cleanupOutlookSafeLinks(rawText: String) -> String {
    guard let outlookSafeLinkRegex else { return rawText }

    var text = rawText
    autoreleasepool {
        // Each pass unwraps the first remaining SafeLink and re-scans, which
        // also handles nested SafeLinks. The loop MUST make forward progress on
        // every iteration or it spins forever: if the `url=` value can't be
        // percent-decoded (an invalid `%` sequence) or the rewrite leaves the
        // text unchanged, the same match is found again every pass. Bound it by
        // a no-progress break and a hard cap so a single malformed SafeLink can
        // never wedge calendar sync.
        let maxPasses = 32
        for _ in 0 ..< maxPasses {
            let matches = outlookSafeLinkRegex.matches(
                in: text, range: NSRange(text.startIndex..., in: text))
            guard let match = matches.first,
                  let fullRange = Range(match.range, in: text)
            else { break }

            let safeLink = String(text[fullRange])
            let encodedTarget = (text as NSString).substring(with: match.range(at: 1))
            guard let decodedTarget = encodedTarget.removingPercentEncoding else { break }

            let updated = text.replacingOccurrences(of: safeLink, with: decodedTarget)
            guard updated != text else { break }
            text = updated
        }
    }
    return text
}

func getMatch(text: String, regex: NSRegularExpression) -> String? {
    var match: String?

    autoreleasepool {
        let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let resultsMap = resultsIterator.compactMap { result -> String? in
            guard let range = Range(result.range, in: text) else { return nil }
            return String(text[range])
        }

        if !resultsMap.isEmpty {
            match = resultsMap[0]
        }
    }

    return match
}

func htmlTagsStrippedForMeetingLinks(_ text: String) -> String {
    if !text.containsHTMLTags {
        return text
    }

    return autoreleasepool {
        guard let dataUTF16 = text.data(using: .utf16) else {
            return text
        }

        let attributedString = NSAttributedString(
            html: dataUTF16,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        )
        return attributedString?.string ?? text
    }
}

extension String {
    fileprivate var containsHTMLTags: Bool {
        range(of: #"</?[A-z][ \t\S]*>"#, options: .regularExpression) != nil
    }
}

// MARK: - Detector

/// Picks the best meeting link from an event's available fields.
///
/// Each available field becomes a `MeetingLinkCandidate` tagged with its
/// `MeetingLinkSource`. Candidates are then ranked by source priority and
/// — within the same source — by URL length, so a Zoom URL with a
/// password/token suffix beats a truncated form of the same link.
///
/// Source order (highest priority first):
///
/// 1. `providerConferenceData` — `conferenceURL` is the structured field set
///    by the provider (Google `conferenceData.entryPoints[type=video]`);
/// 2. `eventURL` — the event's plain URL field;
/// 3. `location` — event location text;
/// 4. `notes` — event notes / description text;
/// 5. `strippedHTMLNotes` — notes after HTML tag/entity stripping;
/// 6. `customRegex` — user-provided fallback patterns over the combined
///    text fields.
///
/// Google Meet URLs are post-processed with an `authuser` query parameter
/// when an account email is available.
enum MeetingLinkDetector {
    static func detect(
        conferenceURL: URL? = nil,
        location: String?,
        eventURL: URL?,
        notes: String?,
        calendarEmail: String?,
        currentUserEmail: String?,
        customRegexes: [String] = []
    ) -> MeetingLink? {
        guard let best = bestCandidate(
            conferenceURL: conferenceURL,
            location: location,
            eventURL: eventURL,
            notes: notes,
            calendarEmail: calendarEmail,
            currentUserEmail: currentUserEmail,
            customRegexes: customRegexes
        ) else { return nil }
        return MeetingLink(service: best.service, url: best.url)
    }

    static func bestCandidate(
        conferenceURL: URL? = nil,
        location: String?,
        eventURL: URL?,
        notes: String?,
        calendarEmail: String?,
        currentUserEmail: String?,
        customRegexes: [String] = []
    ) -> MeetingLinkCandidate? {
        allCandidates(
            conferenceURL: conferenceURL,
            location: location,
            eventURL: eventURL,
            notes: notes,
            calendarEmail: calendarEmail,
            currentUserEmail: currentUserEmail,
            customRegexes: customRegexes
        ).first
    }

    static func allCandidates(
        conferenceURL: URL? = nil,
        location: String?,
        eventURL: URL?,
        notes: String?,
        calendarEmail: String?,
        currentUserEmail: String?,
        customRegexes: [String] = []
    ) -> [MeetingLinkCandidate] {
        let candidates = collectCandidates(
            conferenceURL: conferenceURL,
            location: location,
            eventURL: eventURL,
            notes: notes,
            customRegexes: customRegexes
        )
        return MeetingLinkCandidatePolicy.ranked(from: candidates)
            .map {
                applyMeetAuthuserIfNeeded(
                    candidate: $0,
                    calendarEmail: calendarEmail,
                    currentUserEmail: currentUserEmail
                )
            }
    }

    private static func collectCandidates(
        conferenceURL: URL?,
        location: String?,
        eventURL: URL?,
        notes: String?,
        customRegexes: [String]
    ) -> [MeetingLinkCandidate] {
        var candidates: [MeetingLinkCandidate] = []

        // 1. Provider conference data.
        if let conferenceURL {
            // Run through the regex catalog so we know whether it's Google Meet,
            // Zoom, etc. If it doesn't match any built-in service, classify as
            // `.other` so it still scores at the providerConferenceData priority.
            let service = detectMeetingLink(conferenceURL.absoluteString)?.service ?? .other
            candidates.append(MeetingLinkCandidate(
                url: conferenceURL,
                service: service,
                source: .providerConferenceData
            ))
        }

        // 2. Event URL.
        if let eventURL {
            candidates.append(contentsOf: builtInCandidates(
                in: eventURL.absoluteString,
                source: .eventURL
            ))
        }

        // 3. Location.
        if let location {
            candidates.append(contentsOf: builtInCandidates(
                in: location,
                source: .location
            ))
        }

        if let notes {
            // 4. Raw notes.
            candidates.append(contentsOf: builtInCandidates(
                in: notes,
                source: .notes
            ))

            // 5. Notes after HTML tag/entity stripping. Only contributes when
            //    stripping changes the text — otherwise it would duplicate the
            //    notes candidate.
            let stripped = htmlTagsStrippedForMeetingLinks(notes)
            if stripped != notes {
                candidates.append(contentsOf: builtInCandidates(
                    in: stripped,
                    source: .strippedHTMLNotes
                ))
            }
        }

        // 6. Custom regex fallback over combined text. Lowest priority so a
        //    custom regex cannot override a real provider conference URL.
        if !customRegexes.isEmpty {
            let combined = [location, eventURL?.absoluteString, notes]
                .compactMap { $0 }
                .joined(separator: "\n")
            if let detected = detectCustomRegexLink(text: combined, patterns: customRegexes) {
                candidates.append(MeetingLinkCandidate(
                    url: detected.url,
                    service: detected.service,
                    source: .customRegex
                ))
            }
        }

        return candidates
    }

    private static func builtInCandidates(
        in rawText: String,
        source: MeetingLinkSource
    ) -> [MeetingLinkCandidate] {
        let text = cleanupOutlookSafeLinks(rawText: rawText)
        guard text.contains("://") else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        return MeetingServices.allCases.flatMap { service -> [MeetingLinkCandidate] in
            guard let regex = regex(for: service) else { return [] }
            return regex.matches(in: text, range: range).compactMap { match in
                guard let matchRange = Range(match.range, in: text),
                      let url = URL(string: String(text[matchRange]))
                else { return nil }
                return MeetingLinkCandidate(
                    url: url,
                    service: service,
                    source: source
                )
            }
        }
    }

    private static func detectCustomRegexLink(text: String, patterns: [String]) -> MeetingLink? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let matchRange = Range(match.range, in: text),
               let url = URL(string: String(text[matchRange])) {
                return MeetingLink(service: .other, url: url)
            }
        }
        return nil
    }

    private static func applyMeetAuthuserIfNeeded(
        candidate: MeetingLinkCandidate,
        calendarEmail: String?,
        currentUserEmail: String?
    ) -> MeetingLinkCandidate {
        guard candidate.service == .meet,
              let authAccount = calendarEmail ?? currentUserEmail,
              let urlWithAuth = url(candidate.url, appendingAuthuser: authAccount)
        else { return candidate }
        return MeetingLinkCandidate(
            url: urlWithAuth,
            service: candidate.service,
            source: candidate.source
        )
    }

    private static func url(_ url: URL, appendingAuthuser authAccount: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "authuser" }
        queryItems.append(URLQueryItem(name: "authuser", value: authAccount))
        components.queryItems = queryItems
        return components.url
    }
}

// MARK: - Opening policy

/// Pure decision: given an event with optional meeting link and event URL,
/// what should we do when the user clicks "join"? Side effects (running the
/// script, calling NSWorkspace.open) are performed by `MeetingOpener`.
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
