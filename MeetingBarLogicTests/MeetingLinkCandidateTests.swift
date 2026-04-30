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
        source: MeetingLinkSource
    ) -> MeetingLinkCandidate {
        MeetingLinkCandidate(url: URL(string: url)!, service: service, source: source)
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

    // MARK: - ranked(from:)

    func testRankedSortsByPriorityDescending() {
        let conf = make("https://meet.google.com/abc-defg-hij", service: .meet, source: .providerConferenceData)
        let notes = make("https://us02web.zoom.us/j/123", service: .zoom, source: .notes)
        let custom = make("https://other.com/room/42", source: .customRegex)

        let ranked = MeetingLinkCandidatePolicy.ranked(from: [notes, custom, conf])
        XCTAssertEqual(ranked.map(\.source), [.providerConferenceData, .notes, .customRegex])
    }

    func testRankedDeduplicatesIdenticalURLs() {
        // Same URL collected from two sources — dedup keeps one entry.
        let url = "https://meet.google.com/abc-defg-hij"
        let confSame = make(url, service: .meet, source: .providerConferenceData)
        let notesSame = make(url, service: .meet, source: .notes)

        let ranked = MeetingLinkCandidatePolicy.ranked(from: [confSame, notesSame])
        XCTAssertEqual(ranked.count, 1, "duplicates by URL string collapse to one entry")
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
}
