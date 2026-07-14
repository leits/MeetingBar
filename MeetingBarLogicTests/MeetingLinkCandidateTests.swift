//
//  MeetingLinkCandidateTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class MeetingLinkCandidateTests: XCTestCase {
    private func make(
        _ url: String,
        service: MeetingServices? = .other,
        source: MeetingLinkSource,
        matchLocation: Int = 0
    ) -> MeetingLinkCandidate {
        MeetingLinkCandidate(
            url: URL(string: url)!,
            service: service,
            source: source,
            matchLocation: matchLocation
        )
    }

    // MARK: - best(from:)

    func testBestReturnsNilForEmptyList() {
        XCTAssertNil(MeetingLinkCandidatePolicy.best(from: []))
    }

    func testBestReturnsTheOnlyCandidate() {
        let only = make("https://example.com", source: .notes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [only]), only)
    }

    func testProviderConferenceDataBeatsNotes() {
        let conf = make("https://meet.google.com/abc-defg-hij", service: .meet, source: .providerConferenceData)
        let notes = make("https://us02web.zoom.us/j/123", service: .zoom, source: .notes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [notes, conf]), conf)
    }

    func testEventURLBeatsLocation() {
        let evtURL = make("https://teams.microsoft.com/l/meetup-join/abc", service: .teams, source: .eventURL)
        let loc = make("https://example.com/conf", source: .location)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [loc, evtURL]), evtURL)
    }

    func testLocationBeatsNotes() {
        let loc = make("https://meet.google.com/abc-defg-hij", service: .meet, source: .location)
        let note = make("https://meet.google.com/zzz-yyyy-xxx", service: .meet, source: .notes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [note, loc]), loc)
    }

    func testNotesBeatsStrippedHTMLNotes() {
        let note = make("https://example.com/full", source: .notes)
        let stripped = make("https://example.com/short", source: .strippedHTMLNotes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [stripped, note]), note)
    }

    func testCustomRegexHasLowestPriority() {
        let custom = make("https://internal.corp/room/42", source: .customRegex)
        let stripped = make("https://example.com", source: .strippedHTMLNotes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [custom, stripped]), stripped)
    }

    func testLongerURLBeatsShorterWithinSameSource() {
        // Zoom truncation case: one source has the URL with a password/token
        // suffix, another has a chopped form. We prefer the longer URL because
        // the password is required to actually join the meeting.
        let truncated = make("https://us02web.zoom.us/j/123", service: .zoom, source: .notes)
        let withPassword = make("https://us02web.zoom.us/j/123?pwd=abcdef", service: .zoom, source: .notes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [truncated, withPassword]), withPassword)
    }

    func testSourcePriorityWinsOverURLLength() {
        // A short provider conference URL still beats a long notes URL.
        let shortConf = make("https://meet.google.com/abc", service: .meet, source: .providerConferenceData)
        let longNotes = make("https://us02web.zoom.us/j/12345?pwd=very-long-password-token", service: .zoom, source: .notes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [longNotes, shortConf]), shortConf)
    }

    func testMeetBeatsLongerYouTubeWithinSameSource() {
        // Headline bug: an incidental agenda link in the notes (YouTube) must
        // not beat the real meeting link (Meet) just because its URL is longer.
        // Same source, different services -> service tier decides (conferencing
        // beats content).
        let youtube = make(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL2026-team-agenda-recordings",
            service: .youtube, source: .notes)
        let meet = make("https://meet.google.com/abc-defg-hij", service: .meet, source: .notes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [youtube, meet]), meet)
    }

    func testConferencingBeatsContentDeclaredEarlierInCatalogue() {
        // Slack is declared AFTER YouTube in MeetingServices.allCases and here
        // it also appears later in the field, so the old catalogue-order and
        // appearance-order tiebreaks would both pick YouTube. Service tiering is
        // what makes the real conferencing link win.
        let youtube = make(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL2026-team-agenda-recordings",
            service: .youtube, source: .notes, matchLocation: 0)
        let slack = make(
            "https://app.slack.com/huddle/T1/C1",
            service: .slack, source: .notes, matchLocation: 90)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [youtube, slack]), slack)
    }

    func testSameTierOrdersByFieldPositionNotCatalogue() {
        // Two conferencing services, same source and tier: the link appearing
        // earliest in the field wins. Teams is declared after Zoom in the
        // catalogue but appears first here, so Teams wins.
        let teams = make(
            "https://teams.microsoft.com/l/meetup-join/xyz",
            service: .teams, source: .notes, matchLocation: 0)
        let zoom = make(
            "https://us02web.zoom.us/j/123456",
            service: .zoom, source: .notes, matchLocation: 60)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [zoom, teams]), teams)
    }

    func testSourcePriorityWinsOverServiceTier() {
        // Service tier only breaks ties WITHIN a source: a YouTube link the
        // provider explicitly tagged as the conference still beats a Meet link
        // found in free-text notes.
        let youtubeConf = make("https://www.youtube.com/watch?v=abc123", service: .youtube, source: .providerConferenceData)
        let meetNotes = make("https://meet.google.com/abc-defg-hij", service: .meet, source: .notes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [meetNotes, youtubeConf]), youtubeConf)
    }

    func testCataloguedServiceBeatsNilServiceWithinSameSource() {
        // A candidate matched by any catalogued service — even .other, the
        // last case — outranks an untagged (service: nil) candidate from the
        // same source, regardless of URL length.
        let untagged = make(
            "https://example.com/some/very/long/incidental/link/found/in/notes",
            service: nil, source: .notes)
        let catalogued = make("https://example.com/x", service: .other, source: .notes)
        XCTAssertEqual(MeetingLinkCandidatePolicy.best(from: [untagged, catalogued]), catalogued)
    }

    // MARK: - ranked(from:)

    func testRankedSortsByPriorityDescending() {
        let conf = make("https://meet.google.com/abc-defg-hij", service: .meet, source: .providerConferenceData)
        let notes = make("https://us02web.zoom.us/j/123", service: .zoom, source: .notes)
        let custom = make("https://other.com/room/42", source: .customRegex)

        let ranked = MeetingLinkCandidatePolicy.ranked(from: [notes, custom, conf])
        XCTAssertEqual(ranked.map(\.source), [.providerConferenceData, .notes, .customRegex])
    }

    func testRankedDeduplicatesIdenticalURLs() {
        // Same URL collected from two sources — dedup keeps the highest
        // priority candidate so source metadata remains useful for UI.
        let url = "https://meet.google.com/abc-defg-hij"
        let notesSame = make(url, service: .meet, source: .notes)
        let confSame = make(url, service: .meet, source: .providerConferenceData)

        let ranked = MeetingLinkCandidatePolicy.ranked(from: [notesSame, confSame])
        XCTAssertEqual(ranked.count, 1, "duplicates by URL string collapse to one entry")
        XCTAssertEqual(ranked.first?.source, .providerConferenceData)
    }

    func testRankedOrdersSameSourceByServiceTierNotLength() {
        // Within one source, ranked(from:) must order by service tier
        // (.meet conferencing before .youtube content), not by URL length.
        let youtube = make(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL2026-team-agenda-recordings",
            service: .youtube, source: .notes)
        let meet = make("https://meet.google.com/abc", service: .meet, source: .notes)
        let ranked = MeetingLinkCandidatePolicy.ranked(from: [youtube, meet])
        XCTAssertEqual(ranked.map(\.service), [.meet, .youtube])
    }

    func testRankedReturnsEmptyForEmptyInput() {
        XCTAssertEqual(MeetingLinkCandidatePolicy.ranked(from: []), [])
    }

    // MARK: - priority sanity

    func testEverySourceHasUniquePriority() {
        let sources: [MeetingLinkSource] = [
            .providerConferenceData,
            .eventURL,
            .location,
            .notes,
            .strippedHTMLNotes,
            .customRegex
        ]
        let priorities = sources.map(\.priority)
        XCTAssertEqual(priorities.count, Set(priorities).count,
                       "every source must have a unique priority — best(from:) relies on it")
    }

    func testSourcePriorityOrderingIsExpected() {
        XCTAssertGreaterThan(MeetingLinkSource.providerConferenceData.priority, MeetingLinkSource.eventURL.priority)
        XCTAssertGreaterThan(MeetingLinkSource.eventURL.priority, MeetingLinkSource.location.priority)
        XCTAssertGreaterThan(MeetingLinkSource.location.priority, MeetingLinkSource.notes.priority)
        XCTAssertGreaterThan(MeetingLinkSource.notes.priority, MeetingLinkSource.strippedHTMLNotes.priority)
        XCTAssertGreaterThan(MeetingLinkSource.strippedHTMLNotes.priority, MeetingLinkSource.customRegex.priority)
    }

    // MARK: - MeetingLinkDetector.detect

    func testDetectPrefersMeetOverYouTubeInNotes() {
        // End-to-end: YouTube appears first in the notes, but the real Meet
        // link must still win the Join action / status bar icon.
        let notes = """
        Agenda recording: https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL2026-team-agenda-recordings
        Join: https://meet.google.com/abc-defg-hij
        """
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: notes,
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .meet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testDetectKeepsFieldOrderBetweenSameTierServices() {
        // Two conferencing links in the notes; the earlier one in the text wins
        // even though Teams is declared after Zoom in the catalogue.
        let notes = "First https://teams.microsoft.com/l/meetup-join/abc "
            + "then https://us02web.zoom.us/j/9999"
        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: notes,
            calendarEmail: nil,
            currentUserEmail: nil
        )
        XCTAssertEqual(link?.service, .teams)
    }

    // MARK: - ordering contract & metadata

    func testRankingIsTransitiveAcrossSameServiceDuplicates() {
        // Two Meet links (equal length, so they resolve by URL string) with a
        // Teams link interleaved by position. A naive "position only between
        // different services" comparator is intransitive here and picks Teams;
        // grouping a service's candidates by its earliest position keeps the
        // order total, so a Meet link wins and the result is permutation-stable.
        let meetLate = make(
            "https://meet.google.com/zzz-zzz-zzz", service: .meet, source: .notes, matchLocation: 10)
        let meetEarly = make(
            "https://meet.google.com/aaa-aaa-aaa", service: .meet, source: .notes, matchLocation: 30)
        let teams = make(
            "https://teams.microsoft.com/l/x0000", service: .teams, source: .notes, matchLocation: 20)

        let best = MeetingLinkCandidatePolicy.best(from: [meetLate, meetEarly, teams])
        XCTAssertEqual(best, meetEarly, "a Meet link must win, not the interleaved Teams link")

        let expected = [meetEarly, meetLate, teams]
        for permutation in [[meetLate, meetEarly, teams], [teams, meetLate, meetEarly], [meetEarly, teams, meetLate]] {
            XCTAssertEqual(
                MeetingLinkCandidatePolicy.ranked(from: permutation), expected,
                "ranked order must be stable regardless of input order")
        }
    }

    func testAllCandidatesPreservesMatchLocationThroughAuthuser() {
        // Meet links get an authuser query appended after ranking; that rebuild
        // must carry matchLocation, not reset it to 0.
        let notes = "Prefix text before https://meet.google.com/abc-defg-hij"
        let candidates = MeetingLinkDetector.allCandidates(
            location: nil,
            eventURL: nil,
            notes: notes,
            calendarEmail: nil,
            currentUserEmail: "me@example.com"
        )
        let meet = candidates.first { $0.service == .meet }
        XCTAssertNotNil(meet)
        XCTAssertTrue(
            meet?.url.absoluteString.contains("authuser=me@example.com") == true,
            "Meet URL should carry the authuser query")
        XCTAssertEqual(meet?.matchLocation, 19, "matchLocation must survive the authuser rebuild")
    }
}
