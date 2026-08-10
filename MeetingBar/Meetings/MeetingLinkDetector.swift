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

/// Matches Google's `google.<tld>/url?q=<percent-encoded target>` redirect
/// together with the tracking parameters Google appends after it, whether they
/// arrive as `&` or as the HTML entity `&amp;`.
///
/// The capture group is the encoded target only, which ends at the first `&`.
/// Because the target is *fully* percent-encoded, every `&` after `q=` belongs
/// to Google rather than to the target — so the pattern consumes any trailing
/// `name=value` pair rather than an allow-list of known ones. An unrecognised
/// parameter would otherwise be left glued onto the unwrapped URL, which both
/// defeats the string-identity dedupe in `MeetingLinkCandidatePolicy.ranked`
/// and changes the URL any downstream exact comparison sees.
///
/// The host is matched across country domains (`google.de`, `google.co.uk`),
/// with or without `www.`, because Calendar renders the redirect under the
/// viewer's Google domain. It stays `https`-only and requires `q` to be the
/// first parameter, which is what Calendar emits;
/// `testHostAndSchemeBoundariesAreNotRewritten` records those boundaries.
private let googleRedirectRegex = try? NSRegularExpression(
    pattern: #"https://(?:www\.)?google\.[a-z]{2,}(?:\.[a-z]{2,})?/url\?q=([^\s&"'<>]+)"#
        + #"(?:&(?:amp;)?[A-Za-z][A-Za-z0-9_]*=[^\s&"'<>]*)*"#)

func regex(for service: MeetingServices) -> NSRegularExpression? {
    meetingLinkRegexes[service]
}

func detectMeetingLink(_ rawText: String, customRegexes: [String] = []) -> MeetingLink? {
    let text = cleanupGoogleRedirects(rawText: cleanupOutlookSafeLinks(rawText: rawText))

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
/// `…safelinks.protection.outlook.com/…url=<encoded>` redirect.
///
/// Shares its unwrapping machinery with `cleanupGoogleRedirects`:
/// `unwrappingRedirects` owns the bounded loop, `rewritingRedirects` the
/// per-pass splicing and the skipping of undecodable escapes, and
/// `maxRedirectNestingDepth` documents what the cap does and does not bound.
///
/// The previous loop rewrote one match per pass with a global
/// `replacingOccurrences` and aborted on the first undecodable escape, so a
/// single malformed SafeLink left every later one wrapped, and a body with
/// more than 32 of them left the tail wrapped.
func cleanupOutlookSafeLinks(rawText: String) -> String {
    guard let outlookSafeLinkRegex else { return rawText }
    return unwrappingRedirects(in: rawText, using: outlookSafeLinkRegex)
}

/// Rewrites Google Calendar's `google.<tld>/url?q=…` redirects in `rawText`
/// back to their real targets, so detection sees the underlying meeting URL.
///
/// When Calendar renders an invite body it wraps links in this redirect with
/// the target percent-encoded, so `?pwd=X` becomes `?pwd%3DX`. For a link the
/// organiser typed into the body, Calendar emits both forms — plain and
/// wrapped — and the wrapped one is *longer*, so it wins
/// `MeetingLinkCandidatePolicy`'s length tie-break. Its `pwd` is then not a
/// query parameter at all but part of one valueless parameter name, so no
/// passcode reaches Zoom and the client prompts for one the invite supplied.
/// Links Calendar generates itself, such as the add-on's "Joining
/// instructions", appear wrapped only; those never had a plain form to lose to.
///
/// Shares its unwrapping machinery with `cleanupOutlookSafeLinks`:
/// `unwrappingRedirects` owns the bounded loop, `rewritingRedirects` the
/// per-pass splicing and the skipping of undecodable escapes, and
/// `maxRedirectNestingDepth` documents what the cap does and does not bound.
func cleanupGoogleRedirects(rawText: String) -> String {
    guard let googleRedirectRegex else { return rawText }
    return unwrappingRedirects(in: rawText, using: googleRedirectRegex)
}

/// Bound on redirect *nesting* — a redirect whose decoded target is itself a
/// redirect. Not a bound on how many redirects a body may contain: every match
/// is rewritten per pass, so link count costs no passes at all.
private let maxRedirectNestingDepth = 32

/// Repeatedly unwraps `regex`-matched redirects in `text` until none remain.
///
/// Shared by `cleanupOutlookSafeLinks` and `cleanupGoogleRedirects` so the two
/// cannot drift apart — they previously held separate copies of this loop, and
/// defects fixed in one sat untouched in the other.
///
/// Terminates three ways: `rewritingRedirects` returns nil once no redirects
/// remain (the usual exit) or when no match decoded successfully, and failing
/// both, the text strictly shrinks on every rewriting pass — unwrapping removes
/// a prefix and percent-decoding never lengthens — so the depth cap is a
/// backstop rather than the mechanism.
private func unwrappingRedirects(in text: String, using regex: NSRegularExpression) -> String {
    var text = text
    autoreleasepool {
        for _ in 0 ..< maxRedirectNestingDepth {
            guard let rewritten = rewritingRedirects(in: text, using: regex) else { break }
            text = rewritten
        }
    }
    return text
}

/// One rewrite pass: splices every decodable redirect in `text` with its
/// decoded target, returning nil when nothing changed.
///
/// Builds the result by appending segments rather than mutating in place —
/// `String.Index` values from the match list are only valid against the string
/// they were computed from, and a global `replacingOccurrences` of the matched
/// text would rewrite inside a longer wrapper that happens to start with it.
private func rewritingRedirects(
    in text: String,
    using regex: NSRegularExpression
) -> String? {
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard !matches.isEmpty else { return nil }

    var result = ""
    var copiedUpTo = text.startIndex
    var didRewrite = false

    for match in matches {
        guard let fullRange = Range(match.range, in: text),
              let targetRange = Range(match.range(at: 1), in: text),
              // Upholds the slicing invariant below rather than guarding a
              // diagnosed case: `matches` is non-overlapping and ascending, so
              // this holds today. If that ever stopped being true the slice
              // `text[copiedUpTo ..< fullRange.lowerBound]` would trap.
              fullRange.lowerBound >= copiedUpTo
        else { continue }

        // Skip, don't abort: a malformed escape here must not strand the
        // redirects after it.
        guard let decodedTarget = String(text[targetRange]).removingPercentEncoding
        else { continue }

        result += text[copiedUpTo ..< fullRange.lowerBound]
        result += decodedTarget
        copiedUpTo = fullRange.upperBound
        didRewrite = true
    }

    guard didRewrite else { return nil }
    result += text[copiedUpTo...]
    return result == text ? nil : result
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
            // Same cleanups as `builtInCandidates`. Without them a custom regex
            // — used precisely for hosts the built-in catalogue does not know —
            // matches the wrapped redirect and yields a URL whose `pwd` cannot
            // be parsed. That candidate is also what the "open with another
            // link" menu and the preferences regex tester display.
            let combined = cleanupGoogleRedirects(
                rawText: cleanupOutlookSafeLinks(
                    rawText: [location, eventURL?.absoluteString, notes]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                )
            )
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
        let text = cleanupGoogleRedirects(rawText: cleanupOutlookSafeLinks(rawText: rawText))
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
              let authAccount = currentUserEmail ?? calendarEmail,
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
