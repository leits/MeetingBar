//
//  ZoomGoogleRedirectRegressionTests.swift
//  MeetingBar
//
//  Regression fixture for a Google Calendar Zoom add-on invite body. A link
//  the organiser typed into the body is rendered twice — once plain, once
//  wrapped in a
//  `www.google.com/url?q=` redirect with the target percent-encoded. The
//  wrapped form is LONGER than the plain one, so it used to win the candidate
//  length tie-break, and its `?pwd%3D…` does not parse as a `pwd` query
//  parameter — leaving Zoom to prompt for a passcode the invite supplied.
//
//  Body shape is verbatim from a real invite; all identifiers are fabricated.
//

// swiftlint:disable line_length
// The invite body below is a verbatim fixture; wrapping it would change what
// the detector sees.

import XCTest
@testable import MeetingBarLogic

final class ZoomGoogleRedirectRegressionTests: XCTestCase {
    private let notes = #"""
-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
Join Zoom Meeting
https://acme.zoom.us/j/81234567890?pwd=AbCdEfGhIjKlMnOpQrStUvWxYz1234.1&jst=2 (ID: 81234567890, passcode: 123456)

Join by phone
(US) +1 555-555-5555 (passcode: 123456)

Join using SIP
81234567890@zoomcrc.com (passcode: 123456)

Joining instructions: https://www.google.com/url?q=https://applications.zoom.us/addon/invitation/detail?meetingUuid%3D0000000000000000%253D%253D&sa=D&source=calendar&usg=AOvVaw0000000000000000000

Meeting host: host@example.com<br /><br />Join Zoom Meeting: <br /><a href="https://www.google.com/url?q=https://acme.zoom.us/j/81234567890?pwd%3DAbCdEfGhIjKlMnOpQrStUvWxYz1234.1%26jst%3D2&amp;sa=D&amp;source=calendar&amp;usg=AOvVaw0000000000000000000" target="_blank">https://acme.zoom.us/j/81234567890?pwd=AbCdEfGhIjKlMnOpQrStUvWxYz1234.1&amp;jst=2</a><br /><br />Meeting agenda: <br /><a href="https://www.google.com/url?q=https://docs.zoom.us/agenda/doc/cfe521f4-98ee-4856-b181-f26ca7cd6214?from%3Dgsuite&amp;sa=D&amp;source=calendar&amp;usg=AOvVaw0000000000000000000" target="_blank">https://docs.zoom.us/agenda/doc/cfe521f4-98ee-4856-b181-f26ca7cd6214?from=gsuite</a><br /><br />Chat with Everyone: <br /><a href="https://www.google.com/url?q=https://acme.zoom.us/launch/jc/81234567890&amp;sa=D&amp;source=calendar&amp;usg=AOvVaw0000000000000000000" target="_blank">https://acme.zoom.us/launch/jc/81234567890</a>

Please do not edit this section.
-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
"""#

    func testDetectorPrefersTheLinkWhosePasscodeParses() throws {
        // Fixture guards — a change to the body above must not silently make
        // these assertions vacuous.
        XCTAssertTrue(
            notes.contains("pwd=AbCdEfGhIjKlMnOpQrStUvWxYz1234.1&jst=2"),
            "fixture no longer seeds the plain link")
        XCTAssertTrue(
            notes.contains("pwd%3DAbCdEfGhIjKlMnOpQrStUvWxYz1234.1%26jst%3D2"),
            "fixture no longer seeds the google.com/url wrapped link")

        let link = MeetingLinkDetector.detect(
            location: nil,
            eventURL: nil,
            notes: notes,
            calendarEmail: nil,
            currentUserEmail: nil
        )

        let selected = try XCTUnwrap(link).url
        let items = URLComponents(url: selected, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let pwd = items.first { $0.name == "pwd" }?.value

        XCTAssertEqual(
            pwd, "AbCdEfGhIjKlMnOpQrStUvWxYz1234.1",
            "selected URL must expose a parseable pwd; got \(selected.absoluteString)")
        XCTAssertEqual(
            selected.absoluteString,
            "https://acme.zoom.us/j/81234567890?pwd=AbCdEfGhIjKlMnOpQrStUvWxYz1234.1&jst=2")
    }
}
// swiftlint:enable line_length
