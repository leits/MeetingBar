//
//  GoogleRedirectCleanupTests.swift
//  MeetingBar
//
//  Probes `cleanupGoogleRedirects` directly. The assertion here IS a regex, so
//  mutating the surrounding code proves nothing about it — the table below
//  deliberately includes inputs it must NOT rewrite.
//

import XCTest
@testable import MeetingBarLogic

final class GoogleRedirectCleanupTests: XCTestCase {
    // MARK: - Must rewrite

    func testUnwrapsRedirectAndDecodesQuerySeparators() {
        let wrapped = "Join Zoom Meeting https://www.google.com/url"
            + "?q=https://acme.zoom.us/j/123456789?pwd%3DAbCdEf.1%26jst%3D2"
            + "&amp;sa=D&amp;source=calendar&amp;usg=AOvVaw123"
        let out = cleanupGoogleRedirects(rawText: wrapped)

        XCTAssertEqual(out, "Join Zoom Meeting https://acme.zoom.us/j/123456789?pwd=AbCdEf.1&jst=2")
    }

    func testHandlesLiteralAmpersandSeparators() {
        let wrapped = "https://www.google.com/url?q=https://acme.zoom.us/j/9?pwd%3DX"
            + "&sa=D&source=calendar&usg=AOvVaw9"
        XCTAssertEqual(cleanupGoogleRedirects(rawText: wrapped), "https://acme.zoom.us/j/9?pwd=X")
    }

    func testUnwrapsEveryRedirectInTheText() {
        let wrapped = "a https://www.google.com/url?q=https://acme.zoom.us/j/1?pwd%3DA&amp;sa=D"
            + " b https://www.google.com/url?q=https://acme.zoom.us/j/2?pwd%3DB&amp;sa=D c"
        XCTAssertEqual(
            cleanupGoogleRedirects(rawText: wrapped),
            "a https://acme.zoom.us/j/1?pwd=A b https://acme.zoom.us/j/2?pwd=B c")
    }

    /// Tracking parameters are consumed by name shape, not by an allow-list —
    /// Google appends `opi`, `ved`, `rct`, `cd`, `hl` and others besides the
    /// four that appear in a typical Calendar invite.
    func testConsumesTrailingParametersOutsideTheCommonFour() {
        let wrapped = "https://www.google.com/url?q=https://acme.zoom.us/j/9?pwd%3DX%26jst%3D2"
            + "&amp;sa=D&amp;opi=89978449&amp;ved=2ahUKEwi&amp;usg=AOvVaw0"
        XCTAssertEqual(
            cleanupGoogleRedirects(rawText: wrapped),
            "https://acme.zoom.us/j/9?pwd=X&jst=2",
            "an unrecognised tracking parameter must not be glued onto the target")
    }

    func testUnwrapsCountryCodeGoogleDomains() {
        for host in ["www.google.de", "google.co.uk", "www.google.com.au"] {
            let wrapped = "https://\(host)/url?q=https://acme.zoom.us/j/9?pwd%3DX&amp;sa=D"
            XCTAssertEqual(
                cleanupGoogleRedirects(rawText: wrapped),
                "https://acme.zoom.us/j/9?pwd=X",
                "\(host) should unwrap")
        }
    }

    /// A malformed redirect must not strand the redirects that follow it.
    /// This is the ordering that occurs in practice: Calendar's own generated
    /// "Joining instructions" link precedes the organiser's meeting link.
    func testMalformedRedirectDoesNotStrandLaterOnes() {
        let wrapped = "instructions https://www.google.com/url?q=https://example.com/x%ZZbroken&amp;sa=D"
            + "\njoin https://www.google.com/url?q=https://acme.zoom.us/j/9?pwd%3DX%26jst%3D2&amp;sa=D"
        let out = cleanupGoogleRedirects(rawText: wrapped)

        XCTAssertTrue(out.contains("https://acme.zoom.us/j/9?pwd=X&jst=2"),
                      "the valid redirect after a malformed one must still unwrap; got: \(out)")
        XCTAssertTrue(out.contains("%ZZbroken"), "the malformed one is left as-is; got: \(out)")
    }

    /// `maxNestingDepth` must bound nesting depth, not link count. Filler IDs
    /// are zero-padded so no wrapper is a prefix of another — otherwise a
    /// global-replace implementation clears several per pass and the cap never
    /// bites.
    func testUnwrapsMoreLinksThanTheNestingBudget() {
        let filler = (1 ... 40).map {
            "https://www.google.com/url?q=https://example.com/doc/\(String(format: "%03d", $0))&amp;sa=D"
        }.joined(separator: "\n")
        let wrapped = filler
            + "\nhttps://www.google.com/url?q=https://acme.zoom.us/j/9?pwd%3DX%26jst%3D2&amp;sa=D"
        let out = cleanupGoogleRedirects(rawText: wrapped)

        XCTAssertTrue(out.contains("https://acme.zoom.us/j/9?pwd=X&jst=2"),
                      "a link past the nesting budget must still unwrap")
        XCTAssertFalse(out.contains("google.com/url"), "no wrapper should survive")
    }

    /// One wrapper's matched span can be a prefix of another's — same target,
    /// one with trailing tracking parameters and one without. A global
    /// `replacingOccurrences` of the matched text rewrote inside the longer
    /// wrapper and left its tail glued on; splicing by range does not.
    func testWrapperThatIsAPrefixOfAnotherIsNotRewrittenInside() {
        let wrapped = "a https://www.google.com/url?q=https://acme.zoom.us/j/1?pwd%3DA"
            + " b https://www.google.com/url?q=https://acme.zoom.us/j/1?pwd%3DA&amp;sa=D&amp;usg=Y"
        XCTAssertEqual(
            cleanupGoogleRedirects(rawText: wrapped),
            "a https://acme.zoom.us/j/1?pwd=A b https://acme.zoom.us/j/1?pwd=A")
    }

    // MARK: - Must NOT rewrite

    func testLeavesPlainZoomLinkUntouched() {
        let plain = "https://acme.zoom.us/j/123456789?pwd=AbCdEf.1&jst=2"
        XCTAssertEqual(cleanupGoogleRedirects(rawText: plain), plain)
    }

    /// The real case for this property: a passcode that legitimately contains
    /// percent-encoding, carried *inside* a wrapper. Google double-encodes the
    /// pre-existing `%`, so `pwd=aB%2FcD%3D` arrives as `pwd%3DaB%252FcD%253D`
    /// and exactly one decode is correct. Decoding twice corrupts it.
    ///
    /// The earlier version of this test fed a plain URL with no wrapper, so the
    /// regex never matched and the decode path was never reached — it passed
    /// under a double-decode mutation.
    func testLeavesLegitimatelyEncodedPasscodeUntouched() {
        let wrapped = "https://www.google.com/url?q=https://acme.zoom.us/j/1?pwd%3DaB%252FcD%253D"
            + "&amp;sa=D&amp;usg=AOvVaw0"
        XCTAssertEqual(
            cleanupGoogleRedirects(rawText: wrapped),
            "https://acme.zoom.us/j/1?pwd=aB%2FcD%3D",
            "exactly one decode; a second would corrupt the passcode to aB/cD=")
    }

    func testLeavesMalformedPercentEscapeUntouched() {
        let malformed = "https://www.google.com/url?q=https://acme.zoom.us/j/1?pwd%ZZbroken&amp;sa=D"
        XCTAssertEqual(cleanupGoogleRedirects(rawText: malformed), malformed)
    }

    func testLeavesUnrelatedGoogleURLsUntouched() {
        let docs = "Agenda https://docs.google.com/document/d/abc123/edit"
        XCTAssertEqual(cleanupGoogleRedirects(rawText: docs), docs)
    }

    /// Boundaries the pattern deliberately does not cross. Calendar emits the
    /// lowercase `https://…/url?q=` form; these record what a future loosening
    /// would have to opt into rather than acquire by accident.
    func testHostAndSchemeBoundariesAreNotRewritten() {
        let cases = [
            "https://WWW.GOOGLE.COM/url?q=https://acme.zoom.us/j/1?pwd%3DX&amp;sa=D",
            "http://www.google.com/url?q=https://acme.zoom.us/j/1?pwd%3DX&amp;sa=D",
            "https://www.google.com/url?rct=j&amp;q=https://acme.zoom.us/j/1?pwd%3DX&amp;sa=D",
            "https://notgoogle.com/url?q=https://acme.zoom.us/j/1?pwd%3DX&amp;sa=D"
        ]
        for input in cases {
            XCTAssertEqual(cleanupGoogleRedirects(rawText: input), input, "should not rewrite: \(input)")
        }
    }

    func testEmptyAndPlainTextAreUnchanged() {
        XCTAssertEqual(cleanupGoogleRedirects(rawText: ""), "")
        XCTAssertEqual(cleanupGoogleRedirects(rawText: "no links here"), "no links here")
    }

    // MARK: - Selection consequence, per call site

    func testCleanLinkWinsOverWrappedVariantInNotes() throws {
        let notes = "Join Zoom Meeting\nhttps://acme.zoom.us/j/123456789?pwd=AbCdEf.1&jst=2\n"
            + "Joining instructions: https://www.google.com/url"
            + "?q=https://acme.zoom.us/j/123456789?pwd%3DAbCdEf.1%26jst%3D2&amp;sa=D&amp;usg=AOvVaw1\n"

        XCTAssertTrue(notes.contains("pwd%3DAbCdEf.1"), "fixture no longer seeds the wrapped variant")

        let link = try XCTUnwrap(MeetingLinkDetector.detect(
            location: nil, eventURL: nil, notes: notes,
            calendarEmail: nil, currentUserEmail: nil))

        XCTAssertEqual(link.url.absoluteString, "https://acme.zoom.us/j/123456789?pwd=AbCdEf.1&jst=2")

        let candidates = MeetingLinkDetector.allCandidates(
            location: nil, eventURL: nil, notes: notes,
            calendarEmail: nil, currentUserEmail: nil)
        XCTAssertTrue(
            candidates.allSatisfy { !$0.url.absoluteString.contains("google.com/url") },
            "no wrapped candidate may survive into the alternates menu")
    }

    /// `detectMeetingLink` is the second call site the fix touches, reached by
    /// "open link from clipboard". Reverting its cleanup left the suite green
    /// before this test existed.
    func testStandaloneDetectMeetingLinkUnwrapsRedirect() throws {
        let text = "https://www.google.com/url"
            + "?q=https://acme.zoom.us/j/555000111?pwd%3DZzTop.1%26jst%3D2&amp;sa=D&amp;usg=AOvVaw2"

        let link = try XCTUnwrap(detectMeetingLink(text))
        XCTAssertEqual(link.url.absoluteString, "https://acme.zoom.us/j/555000111?pwd=ZzTop.1&jst=2")
    }

    /// The custom-regex candidate source built its own text and cleaned
    /// nothing, so for a self-hosted service — the reason custom regexes exist
    /// — the only candidate carried an unparseable passcode.
    func testCustomRegexCandidateIsCleanedToo() throws {
        let notes = "Join https://www.google.com/url"
            + "?q=https://meet.acmecorp.internal/room/42?pwd%3DAbCdEf.1%26jst%3D2&amp;sa=D&amp;usg=A1\n"
        let pattern = #"https://meet\.acmecorp\.internal/[^\s]*"#

        let link = try XCTUnwrap(MeetingLinkDetector.detect(
            location: nil, eventURL: nil, notes: notes,
            calendarEmail: nil, currentUserEmail: nil, customRegexes: [pattern]))

        let pwd = URLComponents(url: link.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "pwd" }?.value
        XCTAssertEqual(pwd, "AbCdEf.1", "custom-regex candidate must carry a parseable pwd")
    }
}
