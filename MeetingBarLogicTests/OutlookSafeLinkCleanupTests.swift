//
//  OutlookSafeLinkCleanupTests.swift
//  MeetingBar
//
//  Probes `cleanupOutlookSafeLinks` directly. Like its Google sibling the
//  assertion here IS a regex, so the table includes inputs it must NOT rewrite.
//

import XCTest
@testable import MeetingBarLogic

final class OutlookSafeLinkCleanupTests: XCTestCase {
    private func safeLink(_ encodedTarget: String) -> String {
        "https://acme.safelinks.protection.outlook.com/?url=\(encodedTarget)"
    }

    // MARK: - Must rewrite

    func testUnwrapsSafeLink() {
        let wrapped = safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3DAbC.1")
        XCTAssertEqual(
            cleanupOutlookSafeLinks(rawText: wrapped),
            "https://acme.zoom.us/j/9?pwd=AbC.1")
    }

    /// A malformed SafeLink must not strand the ones after it. Previously the
    /// pass aborted on the first undecodable escape, so a single bad wrapper
    /// anywhere earlier in a body left the real meeting link wrapped — and a
    /// wrapped link's `pwd` is not a parseable query parameter.
    func testMalformedSafeLinkDoesNotStrandLaterOnes() {
        let wrapped = safeLink("https%3A%2F%2Fbad%ZZbroken")
            + "\n" + safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3DAbC.1")
        let out = cleanupOutlookSafeLinks(rawText: wrapped)

        XCTAssertTrue(out.contains("https://acme.zoom.us/j/9?pwd=AbC.1"),
                      "the valid SafeLink after a malformed one must still unwrap; got: \(out)")
        XCTAssertTrue(out.contains("%ZZbroken"), "the malformed one is left as-is; got: \(out)")
    }

    /// The cap must bound nesting depth, not how many SafeLinks a body carries.
    ///
    /// The filler IDs are zero-padded so no wrapper is a prefix of another: an
    /// earlier version used `doc/1 … doc/40`, and the old global
    /// `replacingOccurrences` clobbered `doc/10`-`doc/19` while rewriting
    /// `doc/1`, unwrapping several per pass and hiding the very cap this test
    /// exists to check.
    func testUnwrapsMoreSafeLinksThanTheNestingBudget() {
        let filler = (1 ... 40)
            .map { safeLink("https%3A%2F%2Fexample.com%2Fdoc%2F\(String(format: "%03d", $0))") }
            .joined(separator: "\n")
        let wrapped = filler + "\n" + safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3DAbC.1")
        let out = cleanupOutlookSafeLinks(rawText: wrapped)

        XCTAssertTrue(out.contains("https://acme.zoom.us/j/9?pwd=AbC.1"),
                      "a SafeLink past the nesting budget must still unwrap")
        XCTAssertFalse(out.contains("safelinks.protection.outlook.com"),
                       "no wrapper should survive")
    }

    /// One wrapper's encoded target can be a prefix of another's. The old
    /// global `replacingOccurrences` rewrote inside the longer wrapper and left
    /// its tail encoded; splicing by range does not. Reachable here in a way it
    /// barely is for Google, because the SafeLink capture runs to end-of-
    /// non-whitespace.
    func testWrapperWhoseTargetIsAPrefixOfAnotherIsNotRewrittenInside() {
        let wrapped = safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F1")
            + " " + safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F1%3Fpwd%3DX")
        XCTAssertEqual(
            cleanupOutlookSafeLinks(rawText: wrapped),
            "https://acme.zoom.us/j/1 https://acme.zoom.us/j/1?pwd=X")
    }

    // MARK: - Must NOT rewrite

    func testLeavesPlainLinkUntouched() {
        let plain = "https://acme.zoom.us/j/9?pwd=AbC.1"
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: plain), plain)
    }

    func testLeavesLoneMalformedSafeLinkUntouched() {
        let malformed = safeLink("https%3A%2F%2Fbad%ZZbroken")
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: malformed), malformed)
    }

    func testLeavesUnrelatedOutlookURLsUntouched() {
        let other = "https://outlook.office.com/calendar/item/abc123"
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: other), other)
    }

    func testEmptyAndPlainTextAreUnchanged() {
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: ""), "")
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: "no links here"), "no links here")
    }

    // MARK: - Selection consequence

    /// The SafeLink is the ONLY link in the body — deliberately. Unlike a
    /// Google redirect, which leaves its target unencoded so the Zoom regex
    /// matches inside the wrapper and produces a genuine longer competitor, a
    /// SafeLink percent-encodes its target, so nothing matches inside it and
    /// there is no second candidate to out-rank. With cleanup broken this
    /// event yields no link at all, which is what makes the single-link
    /// fixture the stronger guard: an earlier revision added a plain link
    /// "competitor" and the test then passed with cleanup stubbed out.
    func testDetectionYieldsTheUnwrappedTargetWithAParseablePasscode() throws {
        let notes = "Join " + safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3DAbC.1") + "\n"

        let link = try XCTUnwrap(MeetingLinkDetector.detect(
            location: nil, eventURL: nil, notes: notes,
            calendarEmail: nil, currentUserEmail: nil))

        let pwd = URLComponents(url: link.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "pwd" }?.value
        XCTAssertEqual(pwd, "AbC.1")

        let candidates = MeetingLinkDetector.allCandidates(
            location: nil, eventURL: nil, notes: notes,
            calendarEmail: nil, currentUserEmail: nil)
        XCTAssertTrue(
            candidates.allSatisfy { !$0.url.absoluteString.contains("safelinks.protection.outlook.com") },
            "no wrapped candidate may survive into the alternates menu")
    }
}
