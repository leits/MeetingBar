//
//  EventDocumentDetectorTests.swift
//  MeetingBar
//

import XCTest
@testable import MeetingBarLogic

final class EventDocumentDetectorTests: XCTestCase {
    private func docs(
        attachments: [EventAttachmentInput] = [],
        notes: String? = nil,
        location: String? = nil,
        url: URL? = nil,
        excluded: [URL] = []
    ) -> [EventDocument] {
        EventDocumentDetector.documents(
            attachments: attachments, notes: notes, location: location, eventURL: url, excludedURLs: excluded
        )
    }

    func testGoogleAttachmentUsesProvidedTitleAndMimeKind() {
        let result = docs(attachments: [EventAttachmentInput(
            url: URL(string: "https://docs.google.com/document/d/abc123/edit")!,
            title: "Q4 planning",
            mimeType: "application/vnd.google-apps.document"
        )])
        XCTAssertEqual(result.map(\.title), ["Q4 planning"])
        XCTAssertEqual(result.first?.kind, .googleDocs)
    }

    func testHTMLAnchorTextBecomesTitleAndGoogleRedirectIsResolved() {
        let notes = #"Agenda: <a href="https://www.google.com/url?q=https://www.figma.com/file/XYZ&amp;sa=D&amp;source=calendar&amp;usg=AOv">Design review board</a>"#
        let result = docs(notes: notes)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Design review board")
        XCTAssertEqual(result.first?.url.absoluteString, "https://www.figma.com/file/XYZ")
        XCTAssertEqual(result.first?.kind, .figma)
    }

    func testBareURLFallsBackToTypeOrSiteName() {
        let result = docs(notes: "See https://docs.google.com/spreadsheets/d/s1/edit and https://www.google.com and https://wiki.acme.co.uk/page")
        XCTAssertEqual(result.map(\.title), ["Google Sheets", "Google", "Acme"])
    }

    func testAnchorWhoseTextIsTheURLFallsBack() {
        let result = docs(notes: #"<a href="https://www.notion.so/Spec-1">https://www.notion.so/Spec-1</a>"#)
        XCTAssertEqual(result.first?.title, "Notion")
        XCTAssertFalse(result.first?.hasProvidedTitle ?? true)
    }

    func testIgnoresConferenceAndGoogleMeetBoilerplate() {
        let notes = """
        Join with Google Meet: https://meet.google.com/abc-defg-hij
        Join by phone: https://tel.meet/abc-defg-hij?pin=123
        More phone numbers: https://support.google.com/a/users/answer/9282720
        Zoom: https://acme.zoom.us/j/123456789
        Invitation from Google Calendar: https://calendar.google.com/calendar/event?eid=xyz
        tel:+1-555-0100
        """
        XCTAssertEqual(docs(notes: notes), [])
    }

    func testExcludedURLsAreDropped() {
        let link = URL(string: "https://example.com/custom-meeting")!
        XCTAssertEqual(docs(notes: link.absoluteString, excluded: [link]), [])
    }

    func testDeduplicatesVariantsPreferringProvidedTitle() {
        let attachment = EventAttachmentInput(
            url: URL(string: "https://drive.google.com/open?id=abc123")!, title: "Budget", mimeType: nil
        )
        let notes = "https://docs.google.com/document/d/abc123/edit?usp=sharing https://example.com/a/ https://EXAMPLE.com/a#frag"
        let result = docs(attachments: [attachment], notes: notes)
        XCTAssertEqual(result.map(\.title), ["Budget", "Example"])
    }

    func testMergedAcrossCopiesUpgradesTitle() {
        let plain = docs(notes: "https://docs.google.com/document/d/zz/edit")
        let titled = docs(notes: #"<a href="https://docs.google.com/document/d/zz/view">Notes doc</a>"#)
        XCTAssertEqual(EventDocumentDetector.merged(plain + titled).map(\.title), ["Notes doc"])
    }

    func testOutlookSafeLinkIsResolved() {
        let notes = "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2Facme%2Frepo&data=1"
        let result = docs(notes: notes)
        XCTAssertEqual(result.first?.url.absoluteString, "https://github.com/acme/repo")
        XCTAssertEqual(result.first?.kind, .github)
    }

    func testLocationAndEventURLAreScanned() {
        let result = docs(location: "Room 1, https://miro.com/app/board/x=/", url: URL(string: "https://acme.atlassian.net/wiki/spaces/X"))
        XCTAssertEqual(result.map(\.kind), [.miro, .confluence])
    }

    func testGoogleFileIDAndResolvedTitle() {
        let doc = docs(notes: "https://docs.google.com/document/d/1xNN0RT/edit?tab=t.0#heading=h.e9")[0]
        XCTAssertEqual(doc.googleFileID, "1xNN0RT")
        let resolved = doc.resolved(title: "Blogpost : Session replays", iconURL: URL(string: "https://example.com/i.png"))
        XCTAssertEqual(resolved.title, "Blogpost : Session replays")
        XCTAssertTrue(resolved.hasProvidedTitle)
        XCTAssertEqual(EventDocumentDetector.merged([doc, resolved]).first?.title, "Blogpost : Session replays")
        XCTAssertNil(docs(notes: "https://www.figma.com/file/X")[0].googleFileID)
    }
}
