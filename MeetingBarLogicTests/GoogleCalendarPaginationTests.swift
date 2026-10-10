import Foundation
import XCTest

@testable import MeetingBarLogic

@MainActor
final class GoogleCalendarPaginationTests: XCTestCase {
    private let calendarURL = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true")!
    private let eventsURL = URL(string:
        "https://www.googleapis.com/calendar/v3/calendars/work%40example.com/events"
        + "?singleEvents=true&orderBy=startTime&eventTypes=default"
        + "&timeMin=2026-10-10T00%3A00%3A00Z&timeMax=2026-10-11T00%3A00%3A00Z")!

    private func token(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "pageToken" })?.value
    }

    func testCalendarAndEventListsReadAllPagesIncludingAnEmptyMiddlePage() async throws {
        for originalURL in [calendarURL, eventsURL] {
            var requestedTokens: [String?] = []
            let items = try await GoogleCalendarPagination.fetchAll(from: originalURL) { url in
                let pageToken = self.token(in: url)
                requestedTokens.append(pageToken)
                switch pageToken {
                case nil: return GoogleCalendarPage(items: [["id": "first"]], nextPageToken: "second")
                case "second": return GoogleCalendarPage(items: [], nextPageToken: "last")
                case "last": return GoogleCalendarPage(items: [["id": "third"]])
                default:
                    XCTFail("Unexpected request: \(url)")
                    throw URLError(.badURL)
                }
            }

            XCTAssertEqual(items.compactMap { $0["id"] as? String }, ["first", "third"])
            XCTAssertEqual(requestedTokens, [nil, "second", "last"])
        }
    }

    func testMissingOrEmptyTokenStopsWithoutRequestingAnotherPage() async throws {
        for nextToken in [nil, ""] as [String?] {
            var requestCount = 0
            let items = try await GoogleCalendarPagination.fetchAll(from: calendarURL) { _ in
                requestCount += 1
                return GoogleCalendarPage(items: [], nextPageToken: nextToken)
            }
            XCTAssertTrue(items.isEmpty)
            XCTAssertEqual(requestCount, 1)
        }
    }

    func testPageURLPreservesEncodedQueryAndOpaqueToken() throws {
        let pageToken = "next+/=&?%# Привіт"
        let url = try GoogleCalendarPagination.url(for: eventsURL, pageToken: pageToken)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let original = try XCTUnwrap(URLComponents(url: eventsURL, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, original.scheme)
        XCTAssertEqual(components.host, original.host)
        XCTAssertEqual(components.percentEncodedPath, original.percentEncodedPath)
        XCTAssertEqual(components.percentEncodedQueryItems?.filter { $0.name != "pageToken" }, original.percentEncodedQueryItems)
        XCTAssertEqual(token(in: url), pageToken)
        XCTAssertTrue(components.percentEncodedQuery?.contains("%2B") == true)
    }

    func testPageURLReplacesExistingTokenRatherThanAppendingDuplicates() throws {
        let original = try GoogleCalendarPagination.url(for: calendarURL, pageToken: "old")
        let url = try GoogleCalendarPagination.url(for: original, pageToken: "new")
        let tokens = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.filter { $0.name == "pageToken" }

        XCTAssertEqual(tokens?.count, 1)
        XCTAssertEqual(tokens?.first?.value, "new")
    }

    func testRepeatedTokenFailsInsteadOfLoopingOrReturningPartialItems() async {
        var requestCount = 0
        do {
            _ = try await GoogleCalendarPagination.fetchAll(from: calendarURL) { _ in
                requestCount += 1
                return GoogleCalendarPage(items: [["id": "partial"]], nextPageToken: "repeat")
            }
            XCTFail("Must not return a partial list")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .invalidPagination(calendarURL))
        }
        XCTAssertEqual(requestCount, 2)
    }

    func testLongerTokenCycleFailsAtFirstRepeatedToken() async {
        var requestCount = 0
        do {
            _ = try await GoogleCalendarPagination.fetchAll(from: calendarURL) { _ in
                requestCount += 1
                return GoogleCalendarPage(items: [], nextPageToken: requestCount == 2 ? "two" : "one")
            }
            XCTFail("Must detect a multi-page cycle")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .invalidPagination(calendarURL))
        }
        XCTAssertEqual(requestCount, 3)
    }

    func testLaterPageHTTPFailurePropagatesWithoutReturningPartialItems() async {
        var requestCount = 0
        let failure = GoogleCalendarError.httpStatus(503, url: eventsURL)
        do {
            _ = try await GoogleCalendarPagination.fetchAll(from: eventsURL) { _ in
                requestCount += 1
                if requestCount == 2 { throw failure }
                return GoogleCalendarPage(items: [["id": "partial"]], nextPageToken: "next")
            }
            XCTFail("Must not return a partial success")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, failure)
        }
        XCTAssertEqual(requestCount, 2)
    }

    func testLaterPageAuthFailureRemainsAuthRequired() async {
        do {
            _ = try await GoogleCalendarPagination.fetchAll(from: eventsURL) { url in
                if self.token(in: url) != nil { throw AuthError.notSignedIn }
                return GoogleCalendarPage(items: [["id": "partial"]], nextPageToken: "next")
            }
            XCTFail("Must not swallow authorization failure")
        } catch {
            guard case AuthError.notSignedIn = error else {
                return XCTFail("Expected auth required, got \(error)")
            }
        }
    }

    func testCancelledFetchDoesNotRequestAPage() async {
        let task = Task { @MainActor in
            _ = try await GoogleCalendarPagination.fetchAll(from: calendarURL) { _ in
                XCTFail("A cancelled fetch must not make requests")
                return GoogleCalendarPage(items: [])
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Must propagate cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancellationAfterAPageDiscardsAccumulatedItems() async {
        let task = Task { @MainActor in
            _ = try await GoogleCalendarPagination.fetchAll(from: calendarURL) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return GoogleCalendarPage(items: [["id": "partial"]])
            }
        }
        do {
            try await task.value
            XCTFail("Must not return partial data after cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testJSONPageParsesItemsAndNextToken() throws {
        let data = Data(#"{"items":[{"id":"first"}],"nextPageToken":"next"}"#.utf8)
        let page = try GoogleCalendarPage(data: data, url: calendarURL)

        XCTAssertEqual(page.items.first?["id"] as? String, "first")
        XCTAssertEqual(page.nextPageToken, "next")
    }

    func testValidEmptyJSONPageCanOmitItemsAndStillHaveAnotherPage() throws {
        for kind in ["calendar#calendarList", "calendar#events"] {
            let data = try JSONSerialization.data(withJSONObject: ["kind": kind, "nextPageToken": "next"])
            let page = try GoogleCalendarPage(data: data, url: calendarURL)

            XCTAssertTrue(page.items.isEmpty)
            XCTAssertEqual(page.nextPageToken, "next")
        }
    }

    func testMalformedItemsAreNotTreatedAsAnEmptySuccess() {
        for json in [#"{}"#, #"[]"#, #"{"kind":"calendar#events","items":null}"#, #"{"items":"invalid"}"#] {
            XCTAssertThrowsError(try GoogleCalendarPage(data: Data(json.utf8), url: eventsURL)) { error in
                XCTAssertEqual(error as? GoogleCalendarError, .missingItems(self.eventsURL))
            }
        }
    }

    func testNonStringPageTokenIsRejectedRatherThanTruncatingTheList() {
        let data = Data(#"{"items":[],"nextPageToken":42}"#.utf8)

        XCTAssertThrowsError(try GoogleCalendarPage(data: data, url: calendarURL)) { error in
            XCTAssertEqual(error as? GoogleCalendarError, .invalidPagination(self.calendarURL))
        }
    }
}
