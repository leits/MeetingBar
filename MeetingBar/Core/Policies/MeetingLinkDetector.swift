//
//  MeetingLinkDetector.swift
//  MeetingBar
//

import Foundation

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
