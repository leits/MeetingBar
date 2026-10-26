import XCTest
import Foundation

@testable import MeetingBar

@MainActor
final class GoogleCalendarDataReaderTests: BaseTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-10-18T00:00:00Z")!
    private let end = ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z")!

    private func makeClient(
        respond: @escaping @MainActor (URLRequest) async throws -> (Int, String)
    ) -> GoogleCalendarDataReader {
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                let (status, body) = try await respond(request)
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                )
            },
            accessToken: { _ in "fixture-token" }
        )
        return GoogleCalendarDataReader(userEmail: "owner@example.com") { url, calendarID in
            try await client.fetchJSON(url, calendarID: calendarID)
        }
    }

    func testCalendarListAndPaginatedEventResponseProduceMeetingWithJoinLink() async throws {
        var observedRequests: [URLRequest] = []
        let reader = makeClient { request in
            let url = request.url!
            observedRequests.append(request)
            if url.path.contains("calendarList") {
                return (200, #"""
                {"items":[{"id":"work@example.com","summary":"Engineering","backgroundColor":"#ff0000"},
                          {"id":"personal@example.com","summary":"Personal","backgroundColor":"#00ff00"}]}
                """#)
            }
            if url.path.contains("work@example.com") || url.path.contains("work%40example.com") {
                let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "pageToken" })?.value
                if token == nil {
                    return (200, #"""
                    {"items":[{"id":"standup","summary":"Team standup","status":"confirmed",
                      "start":{"dateTime":"2026-10-18T09:00:00Z"},
                      "end":{"dateTime":"2026-10-18T09:30:00Z"},
                      "conferenceData":{"entryPoints":[{"entryPointType":"video",
                       "uri":"https://meet.google.com/abc-defg-hij"}]}}],
                     "nextPageToken":"last"}
                    """#)
                }
                return (200, #"{"items":[]}"#)
            }
            return (200, #"{"kind":"calendar#events"}"#)
        }

        let calendars = try await reader.fetchCalendars()
        XCTAssertEqual(calendars.map(\.id), ["work@example.com", "personal@example.com"])
        let events = try await reader.fetchEvents(for: calendars, from: start, to: end)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "standup")
        XCTAssertEqual(events.first?.calendar.id, "work@example.com")
        XCTAssertEqual(events.first?.meetingLink?.service, .meet)
        XCTAssertEqual(
            events.first?.meetingLink?.url.absoluteString,
            "https://meet.google.com/abc-defg-hij?authuser=owner@example.com"
        )
        XCTAssertEqual(observedRequests.count, 4)
        let eventRequests = observedRequests.filter {
            $0.url?.path.contains("/events") == true
        }
        XCTAssertEqual(eventRequests.count, 3)
        let formatter = ISO8601DateFormatter()
        for request in eventRequests {
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let parameters = Dictionary(
                (components.queryItems ?? []).compactMap { item -> (String, String)? in
                    guard let value = item.value else { return nil }
                    return (item.name, value)
                },
                uniquingKeysWith: { first, _ in first }
            )
            XCTAssertEqual(parameters["timeMin"], formatter.string(from: start))
            XCTAssertEqual(parameters["timeMax"], formatter.string(from: end))
            XCTAssertEqual(parameters["singleEvents"], "true")
            XCTAssertEqual(parameters["orderBy"], "startTime")
            XCTAssertEqual(parameters["eventTypes"], "default")
            XCTAssertEqual(request.httpMethod, "GET")
        }
        XCTAssertEqual(
            eventRequests.compactMap {
                URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "pageToken" }?.value
            },
            ["last"]
        )
    }

    func testForbiddenCalendarDoesNotHideEventsFromAccessibleCalendar() async throws {
        var restrictedRequests = 0
        let reader = makeClient { request in
            let path = request.url!.path
            if path.contains("restricted") {
                restrictedRequests += 1
                return (403, #"{"error":{"code":403,"errors":[{"reason":"forbidden"}]}}"#)
            }
            return (200, #"""
            {"items":[{"id":"valid","summary":"Available meeting",
              "start":{"dateTime":"2026-10-18T09:00:00Z"},
              "end":{"dateTime":"2026-10-18T09:30:00Z"}}]}
            """#)
        }
        let calendars = [
            MBCalendar(title: "Allowed", id: "allowed", source: nil, email: nil, color: .black),
            MBCalendar(title: "Restricted", id: "restricted", source: nil, email: nil, color: .black)
        ]

        let events = try await reader.fetchEvents(for: calendars, from: start, to: end)
        XCTAssertEqual(events.map(\.id), ["valid"])
        XCTAssertEqual(restrictedRequests, 2)
    }

    func testAllCalendarsForbiddenThrowsInsteadOfReturningEmptySuccess() async {
        var requestedCalendarIDs: [String] = []
        let reader = makeClient { request in
            let path = request.url!.path
            if path.contains("restricted-one") { requestedCalendarIDs.append("restricted-one") }
            if path.contains("restricted-two") { requestedCalendarIDs.append("restricted-two") }
            return (403, #"{"error":{"code":403,"errors":[{"reason":"forbidden"}]}}"#)
        }
        let calendars = [
            MBCalendar(title: "One", id: "restricted-one", source: nil, email: nil, color: .black),
            MBCalendar(title: "Two", id: "restricted-two", source: nil, email: nil, color: .black)
        ]

        do {
            _ = try await reader.fetchEvents(for: calendars, from: start, to: end)
            XCTFail("All inaccessible calendars must fail rather than publish an empty snapshot")
        } catch {
            guard case let GoogleCalendarError.forbiddenCalendar(calendarID, _) = error else {
                return XCTFail("Expected forbidden calendar, got \(error)")
            }
            XCTAssertEqual(calendarID, "restricted-one")
        }
        // Each calendar is retried once after forced token refresh.
        XCTAssertEqual(requestedCalendarIDs, [
            "restricted-one", "restricted-one", "restricted-two", "restricted-two"
        ])
    }

    func testQuotaFailureDiscardsPreviouslyFetchedCalendarEvents() async {
        let reader = makeClient { request in
            if request.url!.path.contains("rate-limited") {
                return (403, #"{"error":{"code":403,"errors":[{"reason":"rateLimitExceeded"}]}}"#)
            }
            return (200, #"""
            {"items":[{"id":"partial","summary":"Should not leak",
              "start":{"dateTime":"2026-10-18T09:00:00Z"},
              "end":{"dateTime":"2026-10-18T09:30:00Z"}}]}
            """#)
        }
        let calendars = [
            MBCalendar(title: "Allowed", id: "allowed", source: nil, email: nil, color: .black),
            MBCalendar(title: "Rate limited", id: "rate-limited", source: nil, email: nil, color: .black)
        ]

        do {
            _ = try await reader.fetchEvents(for: calendars, from: start, to: end)
            XCTFail("Quota errors must not publish an incomplete calendar snapshot")
        } catch {
            guard case let GoogleCalendarError.httpStatus(code, _) = error else {
                return XCTFail("Expected quota HTTP status; got \(error)")
            }
            XCTAssertEqual(code, 403)
        }
    }

    func testMalformedCalendarPageDoesNotAppearAsEmptySuccessfulCalendarList() async {
        let reader = makeClient { _ in
            (200, #"{"items":{}}"#)
        }
        do {
            _ = try await reader.fetchCalendars()
            XCTFail("Invalid calendar list must propagate an error")
        } catch {
            guard case GoogleCalendarError.missingItems = error else {
                return XCTFail("Expected malformed page; got \(error)")
            }
        }
    }
}
