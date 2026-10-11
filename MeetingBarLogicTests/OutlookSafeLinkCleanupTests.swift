//
//  OutlookSafeLinkCleanupTests.swift
//  MeetingBar
//
//  Covers SafeLink cleanup and the meeting URLs selected from wrapped inputs.
//

import XCTest
@testable import MeetingBarLogic

final class OutlookSafeLinkCleanupTests: XCTestCase {
    private func safeLink(_ encodedTarget: String) -> String {
        "https://acme.safelinks.protection.outlook.com/?url=\(encodedTarget)"
    }

    // These ASCII fixture URLs can always be percent-encoded.
    private func wrapSafeLink(_ target: String) -> String {
        safeLink(target.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)
    }

    private func wrapGoogleRedirect(_ target: String) -> String {
        "https://www.google.com/url?q="
            + target.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            + "&sa=D"
    }

    private var targetWithEncodedPasscode: String {
        // A dummy passcode with reserved characters verifies encoding survives cleanup.
        let encoded = "example/passcode=".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return "https://acme.zoom.us/j/9?pwd=\(encoded)&jst=2"
    }

    // MARK: - Must rewrite

    func testUnwrapsSafeLink() {
        let wrapped = safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3Dexample.1")
        XCTAssertEqual(
            cleanupOutlookSafeLinks(rawText: wrapped),
            "https://acme.zoom.us/j/9?pwd=example.1")
    }

    /// A malformed SafeLink must not strand the ones after it. Previously the
    /// pass aborted on the first undecodable escape, so a single bad wrapper
    /// anywhere earlier in a body left the real meeting link wrapped — and a
    /// wrapped link's `pwd` is not a parseable query parameter.
    func testMalformedSafeLinkDoesNotStrandLaterOnes() {
        let wrapped = safeLink("https%3A%2F%2Fbad%ZZbroken")
            + "\n" + safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3Dexample.1")
        let out = cleanupOutlookSafeLinks(rawText: wrapped)

        XCTAssertTrue(out.contains("https://acme.zoom.us/j/9?pwd=example.1"),
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
        let wrapped = filler + "\n" + safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3Dexample.1")
        let out = cleanupOutlookSafeLinks(rawText: wrapped)

        XCTAssertTrue(out.contains("https://acme.zoom.us/j/9?pwd=example.1"),
                      "a SafeLink past the nesting budget must still unwrap")
        XCTAssertFalse(out.contains("safelinks.protection.outlook.com"),
                       "no wrapper should survive")
    }

    /// Splicing by range must not rewrite the prefix of a longer wrapper.
    func testWrapperWhoseTargetIsAPrefixOfAnotherIsNotRewrittenInside() {
        let wrapped = safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F1")
            + " " + safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F1%3Fpwd%3DX")
        XCTAssertEqual(
            cleanupOutlookSafeLinks(rawText: wrapped),
            "https://acme.zoom.us/j/1 https://acme.zoom.us/j/1?pwd=X")
    }

    func testTrackingParametersAreRemovedWithoutDecodingPasscodeTwice() {
        let target = targetWithEncodedPasscode
        for separator in ["&", "&amp;"] {
            let wrapped = wrapSafeLink(target)
                + separator + "data=tracking%ZZ" + separator + "sdata=signature%3D" + separator + "reserved=0"
            XCTAssertEqual(cleanupOutlookSafeLinks(rawText: wrapped), target)
        }
    }

    func testTargetParameterAfterTrackingParametersIsRecognized() {
        let encoded = "https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3DX"
        for separator in ["&", "&amp;"] {
            let wrapped = "https://acme.safelinks.protection.outlook.com/?data=tracking"
                + separator + "url=" + encoded + separator + "reserved=0"
            XCTAssertEqual(cleanupOutlookSafeLinks(rawText: wrapped), "https://acme.zoom.us/j/9?pwd=X")
        }
    }

    func testHTMLAttributeBoundariesArePreserved() {
        let wrapped = "<a href=\"" + wrapSafeLink("https://acme.zoom.us/j/9?pwd=X")
            + "&amp;reserved=0\">Join</a>"
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: wrapped), "<a href=\"https://acme.zoom.us/j/9?pwd=X\">Join</a>")
    }

    func testNestedSafeLinksStopAtTheDepthBudget() {
        let target = "https://acme.zoom.us/j/9?pwd=X"
        let atBudget = (0 ..< 32).reduce(target) { wrapped, _ in wrapSafeLink(wrapped) }
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: atBudget), target)

        let overBudget = wrapSafeLink(atBudget)
        let partiallyUnwrapped = cleanupOutlookSafeLinks(rawText: overBudget)
        XCTAssertEqual(partiallyUnwrapped, wrapSafeLink(target))
    }

    // MARK: - Must NOT rewrite

    func testLeavesPlainLinkUntouched() {
        let plain = "https://acme.zoom.us/j/9?pwd=example.1"
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

    func testUnrelatedHostsAndParametersAreNotRewritten() {
        let encoded = "https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3DX"
        let cases = [
            "https://acme.safelinks.protection.outlook.com.evil.example/?url=\(encoded)",
            "https://acme.safelinks.protection.outlook.com/?noturl=\(encoded)",
            "https://acme.safelinks.protection.outlook.com/?data=url=\(encoded)",
            "http://acme.safelinks.protection.outlook.com/?url=\(encoded)",
            "https://acme.safelinks.protection.outlook.com/?url="
        ]
        for input in cases {
            XCTAssertEqual(cleanupOutlookSafeLinks(rawText: input), input)
        }
    }

    func testEmptyAndPlainTextAreUnchanged() {
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: ""), "")
        XCTAssertEqual(cleanupOutlookSafeLinks(rawText: "no links here"), "no links here")
    }

    // MARK: - Selection consequence

    /// Use only a wrapped link so a plain alternative cannot mask broken cleanup.
    func testDetectionYieldsTheUnwrappedTargetWithAParseablePasscode() throws {
        let notes = "Join " + safeLink("https%3A%2F%2Facme.zoom.us%2Fj%2F9%3Fpwd%3Dexample.1") + "\n"

        let link = try XCTUnwrap(MeetingLinkDetector.detect(
            location: nil, eventURL: nil, notes: notes,
            calendarEmail: nil, currentUserEmail: nil))

        let pwd = URLComponents(url: link.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "pwd" }?.value
        XCTAssertEqual(pwd, "example.1")
    }

    func testDetectionUnwrapsBothMixedNestingOrders() throws {
        let target = targetWithEncodedPasscode
        let inputs = [
            wrapGoogleRedirect(wrapSafeLink(target)),
            wrapSafeLink(wrapGoogleRedirect(target)),
            wrapGoogleRedirect(wrapSafeLink(wrapGoogleRedirect(wrapSafeLink(target))))
        ]
        for input in inputs {
            let clipboardLink = try XCTUnwrap(detectMeetingLink(input))
            XCTAssertEqual(clipboardLink.url.absoluteString, target)

            let noteLink = try XCTUnwrap(MeetingLinkDetector.detect(
                location: nil, eventURL: nil, notes: input,
                calendarEmail: nil, currentUserEmail: nil))
            XCTAssertEqual(noteLink.url.absoluteString, target)

            let candidates = MeetingLinkDetector.allCandidates(
                location: nil, eventURL: nil, notes: input,
                calendarEmail: nil, currentUserEmail: nil)
            XCTAssertFalse(candidates.isEmpty)
            XCTAssertTrue(candidates.allSatisfy { $0.url.absoluteString == target })
        }
    }

    func testCustomRegexUnwrapsMixedRedirects() throws {
        let target = "https://meet.acmecorp.internal/room/42?pwd=X"
        let wrapped = wrapGoogleRedirect(wrapSafeLink(target))
        let pattern = #"https://meet\.acmecorp\.internal/[^\s]*"#
        let link = try XCTUnwrap(MeetingLinkDetector.detect(
            location: nil, eventURL: nil, notes: wrapped,
            calendarEmail: nil, currentUserEmail: nil, customRegexes: [pattern]))
        XCTAssertEqual(link.url.absoluteString, target)
    }
}
