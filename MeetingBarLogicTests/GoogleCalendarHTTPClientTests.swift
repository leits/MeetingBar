import Foundation
import XCTest

@testable import MeetingBarLogic

@MainActor
final class GoogleCalendarHTTPClientTests: XCTestCase {
    private let eventsURL = URL(
        string: "https://www.googleapis.com/calendar/v3/calendars/team%40example.com/events?singleEvents=true"
    )!

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    nonisolated private static func pageToken(in request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "pageToken" })?.value
    }

    func testRealRequestPipelineAuthenticatesAndPaginatesAllPages() async throws {
        var requests: [URLRequest] = []
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                requests.append(request)
                switch Self.pageToken(in: request) {
                case nil:
                    return (
                        Data(#"{"items":[{"id":"first"}],"nextPageToken":"next+page"}"#.utf8),
                        Self.response(for: request, status: 200)
                    )
                case "next+page":
                    return (
                        Data(#"{"items":[{"id":"second"}]}"#.utf8),
                        Self.response(for: request, status: 200)
                    )
                default:
                    XCTFail("Unexpected page token")
                    throw URLError(.badURL)
                }
            },
            accessToken: { force in
                XCTAssertFalse(force)
                return "test-access-token"
            }
        )

        let items = try await client.fetchJSON(eventsURL, calendarID: "team@example.com")

        XCTAssertEqual(items.compactMap { $0["id"] as? String }, ["first", "second"])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") },
                       ["Bearer test-access-token", "Bearer test-access-token"])
        XCTAssertEqual(requests.map(Self.pageToken(in:)), [nil, "next+page"])
        XCTAssertTrue(requests[1].url!.absoluteString.contains("next%2Bpage"))
    }

    func test401RefreshesTokenThenRetriesSameRequestWithNewToken() async throws {
        var activeToken = "expired-token"
        var forcedRefreshCount = 0
        var requests: [URLRequest] = []
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                requests.append(request)
                let firstAttempt = requests.count == 1
                return (
                    Data((firstAttempt ? #"{"error":{"code":401}}"# : #"{"items":[{"id":"recovered"}]}"#).utf8),
                    Self.response(for: request, status: firstAttempt ? 401 : 200)
                )
            },
            accessToken: { force in
                if force {
                    forcedRefreshCount += 1
                    activeToken = "fresh-token"
                }
                return activeToken
            }
        )

        let items = try await client.fetchJSON(eventsURL, calendarID: "team@example.com")

        XCTAssertEqual(items.first?["id"] as? String, "recovered")
        XCTAssertEqual(forcedRefreshCount, 1)
        XCTAssertEqual(
            requests.map { $0.value(forHTTPHeaderField: "Authorization") },
            ["Bearer expired-token", "Bearer fresh-token"]
        )
        XCTAssertEqual(requests.compactMap(\.url), [eventsURL, eventsURL])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[1].httpMethod, requests[0].httpMethod)
    }

    func testSecond401RequiresReconnectionWithoutInfiniteRetry() async {
        var attempts = 0
        var forcedRefreshCount = 0
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                attempts += 1
                return (Data(#"{"error":{"code":401}}"#.utf8), Self.response(for: request, status: 401))
            },
            accessToken: { force in
                if force { forcedRefreshCount += 1 }
                return "still-rejected"
            }
        )

        do {
            _ = try await client.fetchJSON(eventsURL)
            XCTFail("Expected authentication failure")
        } catch {
            guard case AuthError.notSignedIn = error else {
                return XCTFail("Expected auth-required error, got \(error)")
            }
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(forcedRefreshCount, 1)
    }

    func test403AfterForcedRefreshReportsForbiddenCalendar() async {
        var activeToken = "previous-token"
        var forcedRefreshCount = 0
        var requests: [URLRequest] = []
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                requests.append(request)
                return (
                    Data(#"{"error":{"code":403}}"#.utf8),
                    Self.response(for: request, status: 403)
                )
            },
            accessToken: { force in
                if force {
                    forcedRefreshCount += 1
                    activeToken = "refreshed-token"
                }
                return activeToken
            }
        )

        do {
            _ = try await client.fetchJSON(eventsURL, calendarID: "team@example.com")
            XCTFail("A persistently forbidden calendar must not appear as an empty success")
        } catch {
            XCTAssertEqual(
                error as? GoogleCalendarError,
                .forbiddenCalendar(calendarID: "team@example.com", url: eventsURL)
            )
        }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(forcedRefreshCount, 1)
        XCTAssertEqual(
            requests.map { $0.value(forHTTPHeaderField: "Authorization") },
            ["Bearer previous-token", "Bearer refreshed-token"]
        )
    }

    func testFailedForcedRefreshPropagatesWithoutAnotherHTTPRequest() async {
        var requestCount = 0
        var refreshCount = 0
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                requestCount += 1
                return (
                    Data(#"{"error":{"code":401}}"#.utf8),
                    Self.response(for: request, status: 401)
                )
            },
            accessToken: { force in
                if force {
                    refreshCount += 1
                    throw AuthError.temporarilyUnavailable(underlying: URLError(.notConnectedToInternet))
                }
                return "expired-token"
            }
        )

        do {
            _ = try await client.fetchJSON(eventsURL)
            XCTFail("Token refresh error must propagate")
        } catch {
            guard case AuthError.temporarilyUnavailable = error else {
                return XCTFail("Expected transient auth error, got \(error)")
            }
        }
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(refreshCount, 1)
    }

    func testTransportFailurePropagatesRatherThanReturningNoEvents() async {
        var requestCount = 0
        let client = GoogleCalendarHTTPClient(
            transport: { _ in
                requestCount += 1
                throw URLError(.notConnectedToInternet)
            },
            accessToken: { _ in "token" }
        )

        do {
            _ = try await client.fetchJSON(eventsURL)
            XCTFail("Network errors must not become empty calendar results")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testCancellationDuringForcedRefreshPreventsAnotherHTTPRequest() async {
        var requestCount = 0
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                requestCount += 1
                return (
                    Data(#"{"error":{"code":401}}"#.utf8),
                    Self.response(for: request, status: 401)
                )
            },
            accessToken: { force in
                if force {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return "refreshed-token"
                }
                return "expired-token"
            }
        )

        let task = Task { @MainActor in
            try await client.fetchJSON(eventsURL)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled retries must not issue another request")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testLaterPageServerFailureDoesNotReturnEarlierEvents() async {
        var requests = 0
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                requests += 1
                if requests == 1 {
                    return (
                        Data(#"{"items":[{"id":"partial"}],"nextPageToken":"next"}"#.utf8),
                        Self.response(for: request, status: 200)
                    )
                }
                return (
                    Data(#"{"error":{"code":503}}"#.utf8),
                    Self.response(for: request, status: 503)
                )
            },
            accessToken: { _ in "token" }
        )

        do {
            _ = try await client.fetchJSON(eventsURL)
            XCTFail("Partial results must not be returned on failure")
        } catch {
            guard case let GoogleCalendarError.httpStatus(status, _) = error else {
                return XCTFail("Expected HTTP status error, got \(error)")
            }
            XCTAssertEqual(status, 503)
        }
        XCTAssertEqual(requests, 2)
    }

    func testMalformedResponseIsNotTreatedAsEmptyCalendar() async {
        let client = GoogleCalendarHTTPClient(
            transport: { request in
                (Data(#"{"items":"not-an-array"}"#.utf8), Self.response(for: request, status: 200))
            },
            accessToken: { _ in "token" }
        )

        do {
            _ = try await client.fetchJSON(eventsURL)
            XCTFail("Invalid response should not appear as a successful empty page")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .missingItems(eventsURL))
        }
    }
}
