//
//  GCEventStoreTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class GCEventStoreTests: XCTestCase {
    private let calendar = MBCalendar(title: "Test", id: "test", source: nil, email: nil, color: .black)

    private func baseItem() -> [String: Any] {
        [
            "id": "evt1",
            "start": ["dateTime": "2025-01-01T10:00:00Z"],
            "end": ["dateTime": "2025-01-01T11:00:00Z"]
        ]
    }

    func testParsesGoogleDocAttachmentAsMeetingNotes() {
        var item = baseItem()
        item["attachments"] = [
            [
                "fileUrl": "https://docs.google.com/document/d/abc123/edit",
                "title": "Standup - Notes",
                "mimeType": "application/vnd.google-apps.document",
                "fileId": "abc123"
            ]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertEqual(event?.meetingNotesDocLink?.absoluteString,
                       "https://docs.google.com/document/d/abc123/edit")
    }

    func testIgnoresNonDocumentAttachment() {
        var item = baseItem()
        item["attachments"] = [
            [
                "fileUrl": "https://drive.google.com/file/d/xyz/view",
                "title": "Slides.pdf",
                "mimeType": "application/pdf",
                "fileId": "xyz"
            ]
        ]

        let event = GCEventStore.GCParser.event(from: item, calendar: calendar)

        XCTAssertNil(event?.meetingNotesDocLink)
    }

    func testNoAttachmentsLeavesMeetingNotesNil() {
        let event = GCEventStore.GCParser.event(from: baseItem(), calendar: calendar)

        XCTAssertNil(event?.meetingNotesDocLink)
    }
}
