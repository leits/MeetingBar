//
//  GoogleDriveMetadataResolverTests.swift
//  MeetingBarTests
//
//  Drive title lookups for invite documents (#917): the request shape, how
//  responses are applied, and caching. No network; the transport is stubbed.
//

import XCTest

@testable import MeetingBar

@MainActor
final class GoogleDriveMetadataResolverTests: XCTestCase {
    private let calendar = MBCalendar(
        title: "Calendar", id: "calendar-id", source: nil, email: nil, color: .black
    )
    private let docURL = "https://docs.google.com/document/d/FILE123/edit"

    /// Records requests and answers each with a canned status and body.
    private final class StubTransport: @unchecked Sendable {
        var requests: [URLRequest] = []
        var status = 200
        var body: [String: Any] = ["name": "Q3 planning", "iconLink": "https://example.com/16/type/doc"]
        var error: Error?

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            if let error { throw error }
            let data = try JSONSerialization.data(withJSONObject: body)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    private func makeResolver(_ stub: StubTransport, token: String = "token-abc") -> GoogleDriveMetadataResolver {
        GoogleDriveMetadataResolver(
            transport: { try await stub.send($0) },
            accessToken: { token }
        )
    }

    private func event(notes: String?, attachments: [EventAttachmentInput] = []) -> MBEvent {
        MBEvent(
            id: "event-1",
            lastModifiedDate: nil,
            title: "Planning",
            status: .confirmed,
            notes: notes,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            isAllDay: false,
            recurrent: false,
            calendar: calendar,
            attachments: attachments
        )
    }

    func testReplacesFallbackTitleWithDriveName() async {
        let stub = StubTransport()
        let events = await makeResolver(stub).resolveDocuments(in: [event(notes: "Doc: \(docURL)")])

        let document = events.first?.documents.first
        XCTAssertEqual(document?.title, "Q3 planning")
        XCTAssertEqual(document?.iconURL?.absoluteString, "https://example.com/16/type/doc")
        XCTAssertEqual(document?.hasProvidedTitle, true)
    }

    func testRequestsOnlyMetadataFieldsWithBearerToken() async throws {
        let stub = StubTransport()
        _ = await makeResolver(stub).resolveDocuments(in: [event(notes: docURL)])

        let request = try XCTUnwrap(stub.requests.first)
        let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(components.host, "www.googleapis.com")
        XCTAssertEqual(components.path, "/drive/v3/files/FILE123")
        XCTAssertEqual(components.queryItems?.first { $0.name == "fields" }?.value, "name,iconLink")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-abc")
    }

    func testKeepsFallbackTitleWhenFileIsInaccessible() async {
        let stub = StubTransport()
        stub.status = 404
        let original = event(notes: docURL)
        let events = await makeResolver(stub).resolveDocuments(in: [original])

        XCTAssertEqual(events.first?.documents, original.documents)
    }

    func testKeepsFallbackTitleWhenTransportFails() async {
        let stub = StubTransport()
        stub.error = URLError(.notConnectedToInternet)
        let original = event(notes: docURL)
        let events = await makeResolver(stub).resolveDocuments(in: [original])

        XCTAssertEqual(events.first?.documents, original.documents)
    }

    func testCachesLookupsIncludingFailures() async {
        let stub = StubTransport()
        let resolver = makeResolver(stub)
        _ = await resolver.resolveDocuments(in: [event(notes: docURL)])
        _ = await resolver.resolveDocuments(in: [event(notes: docURL)])
        XCTAssertEqual(stub.requests.count, 1)

        let failing = StubTransport()
        failing.status = 403
        let failingResolver = makeResolver(failing)
        _ = await failingResolver.resolveDocuments(in: [event(notes: docURL)])
        _ = await failingResolver.resolveDocuments(in: [event(notes: docURL)])
        XCTAssertEqual(failing.requests.count, 1)
    }

    func testSkipsDocumentsThatAlreadyHaveATitle() async {
        let stub = StubTransport()
        let attachment = EventAttachmentInput(
            url: URL(string: docURL)!,
            title: "Agenda",
            mimeType: "application/vnd.google-apps.document"
        )
        let events = await makeResolver(stub).resolveDocuments(in: [event(notes: nil, attachments: [attachment])])

        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(events.first?.documents.first?.title, "Agenda")
    }

    func testLooksUpEachFileOnceAcrossEvents() async {
        let stub = StubTransport()
        _ = await makeResolver(stub).resolveDocuments(in: [
            event(notes: docURL),
            event(notes: "Same doc again: \(docURL)")
        ])
        XCTAssertEqual(stub.requests.count, 1)
    }

    func testGoogleAttachmentsAreParsedIntoDocuments() {
        let event = GCEventStore.GCParser.event(
            from: [
                "id": "event-2",
                "summary": "Review",
                "status": "confirmed",
                "start": ["dateTime": "2026-04-24T10:00:00Z"],
                "end": ["dateTime": "2026-04-24T10:30:00Z"],
                "attachments": [
                    [
                        "fileUrl": "https://drive.google.com/open?id=SHEET1",
                        "title": "Budget",
                        "mimeType": "application/vnd.google-apps.spreadsheet"
                    ]
                ]
            ],
            calendar: calendar
        )

        let document = event?.documents.first
        XCTAssertEqual(document?.title, "Budget")
        XCTAssertEqual(document?.kind, .googleSheets)
    }
}
