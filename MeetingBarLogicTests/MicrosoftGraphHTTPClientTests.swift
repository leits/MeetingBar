import Foundation
import XCTest

@testable import MeetingBarLogic

@MainActor
final class MicrosoftGraphHTTPClientTests: XCTestCase {
    private let firstURL = URL(string: "https://graph.microsoft.com/v1.0/me/calendars/work/calendarView?$top=250")!
    private let secondLink = "https://graph.microsoft.com/v1.0/me/calendars/work/calendarView?$skip=250"

    private static func response(
        for request: URLRequest,
        status: Int,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    private struct Stub {
        let body: String
        let status: Int
        let headers: [String: String]?

        init(_ body: String, _ status: Int, _ headers: [String: String]? = nil) {
            self.body = body
            self.status = status
            self.headers = headers
        }
    }

    private func client(
        pages: @escaping @MainActor (URLRequest, Int) throws -> Stub,
        sleep: @escaping MicrosoftGraphHTTPClient.Sleep = { _ in },
        accessToken: @escaping MicrosoftGraphHTTPClient.AccessToken = { _ in "token" }
    ) -> (MicrosoftGraphHTTPClient, () -> [URLRequest]) {
        var requests: [URLRequest] = []
        let client = MicrosoftGraphHTTPClient(
            transport: { request in
                requests.append(request)
                let stub = try pages(request, requests.count)
                return (Data(stub.body.utf8), Self.response(for: request, status: stub.status, headers: stub.headers))
            },
            accessToken: accessToken,
            sleep: sleep
        )
        return (client, { requests })
    }

    func testReadsEveryPageWithAuthorizationAndPreferHeaders() async throws {
        let link = secondLink
        let (client, requests) = client(pages: { _, count in
            count == 1
                ? Stub(#"{"value":[{"id":"first"}],"@odata.nextLink":"\#(link)"}"#, 200)
                : Stub(#"{"value":[{"id":"second"}]}"#, 200)
        })

        let items = try await client.fetchItems(firstURL, calendarID: "work")

        XCTAssertEqual(items.compactMap { $0["id"] as? String }, ["first", "second"])
        XCTAssertEqual(requests().map(\.url?.absoluteString), [firstURL.absoluteString, link])
        XCTAssertEqual(requests().first?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertTrue(requests().first?.value(forHTTPHeaderField: "Prefer")?.contains("outlook.timezone") ?? false)
    }

    func testValidEmptyPageReturnsNoItems() async throws {
        let (client, _) = client(pages: { _, _ in Stub(#"{"value":[]}"#, 200) })
        let items = try await client.fetchItems(firstURL)
        XCTAssertTrue(items.isEmpty)
    }

    func testMissingValueFailsInsteadOfLookingLikeAnEmptyCalendar() async {
        let (client, _) = client(pages: { _, _ in Stub(#"{"unexpected":true}"#, 200) })
        await assertThrows(client, .malformedResponse(firstURL))
    }

    func testForeignNextLinkFailsWithoutSendingTheToken() async {
        let (client, requests) = client(pages: { _, _ in
            Stub(#"{"value":[{"id":"first"}],"@odata.nextLink":"https://attacker.example/page"}"#, 200)
        })
        await assertThrows(client, .invalidPagination(firstURL))
        XCTAssertEqual(requests().count, 1)
    }

    func testRepeatedNextLinkFailsInsteadOfLooping() async {
        let link = firstURL.absoluteString
        let (client, requests) = client(pages: { _, _ in
            Stub(#"{"value":[],"@odata.nextLink":"\#(link)"}"#, 200)
        })
        await assertThrows(client, .invalidPagination(firstURL))
        XCTAssertEqual(requests().count, 1)
    }

    func testLaterPageFailureDiscardsEarlierPages() async {
        let link = secondLink
        let (client, _) = client(pages: { _, count in
            count == 1
                ? Stub(#"{"value":[{"id":"first"}],"@odata.nextLink":"\#(link)"}"#, 200)
                : Stub(#"{"error":{"code":"InternalServerError"}}"#, 500)
        })
        do {
            _ = try await client.fetchItems(firstURL)
            XCTFail("Expected a failure rather than a partial list")
        } catch {
            guard case .httpStatus(500, "InternalServerError", _)? = error as? MicrosoftGraphError else {
                return XCTFail("Got \(error)")
            }
        }
    }

    func test401RefreshesTokenThenRetriesTheSamePage() async throws {
        var forced: [Bool] = []
        let (client, requests) = client(
            pages: { _, count in
                count == 1 ? Stub(#"{"error":{"code":"InvalidAuthenticationToken"}}"#, 401) : Stub(#"{"value":[{"id":"ok"}]}"#, 200)
            },
            accessToken: { force in
                forced.append(force)
                return force || forced.count > 1 ? "fresh" : "stale"
            }
        )

        let items = try await client.fetchItems(firstURL)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(forced, [false, true, false])
        XCTAssertEqual(requests().map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer stale", "Bearer fresh"])
    }

    func testRepeated401RequiresSignIn() async {
        let (client, requests) = client(pages: { _, _ in Stub("{}", 401) })
        do {
            _ = try await client.fetchItems(firstURL)
            XCTFail("Expected notSignedIn")
        } catch {
            XCTAssertEqual(error as? MicrosoftAuthError, .notSignedIn)
        }
        XCTAssertEqual(requests().count, 2)
    }

    func testThrottledPageWaitsForRetryAfterThenRetries() async throws {
        var delays: [TimeInterval] = []
        let (client, requests) = client(
            pages: { _, count in
                count == 1 ? Stub("{}", 429, ["Retry-After": "3"]) : Stub(#"{"value":[{"id":"ok"}]}"#, 200)
            },
            sleep: { delays.append($0) }
        )

        let items = try await client.fetchItems(firstURL)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(delays, [3])
        XCTAssertEqual(requests().count, 2)
    }

    func testForbiddenCalendarKeepsItsIdentity() async {
        let (client, _) = client(pages: { _, _ in Stub(#"{"error":{"code":"ErrorAccessDenied"}}"#, 403) })
        do {
            _ = try await client.fetchItems(firstURL, calendarID: "work")
            XCTFail("Expected forbiddenCalendar")
        } catch {
            XCTAssertEqual(error as? MicrosoftGraphError, .forbiddenCalendar(calendarID: "work", url: firstURL))
        }
    }

    func testCancellationStopsBeforeTheNextPage() async {
        let link = secondLink
        let (client, requests) = client(pages: { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return Stub(#"{"value":[],"@odata.nextLink":"\#(link)"}"#, 200)
        })
        do {
            _ = try await client.fetchItems(firstURL)
            XCTFail("Expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError, "Got \(error)")
        }
        XCTAssertEqual(requests().count, 1)
    }

    private func assertThrows(
        _ client: MicrosoftGraphHTTPClient,
        _ expected: MicrosoftGraphError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await client.fetchItems(firstURL)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? MicrosoftGraphError, expected, file: file, line: line)
        }
    }
}

@MainActor
final class MicrosoftGraphAuthFlowTests: XCTestCase {
    func testWaitReturnsTheCallbackResultAndCancelsTheDeadline() async throws {
        let value = try await MicrosoftGraphCallbackWait.wait(
            timeout: 30,
            timeoutError: MicrosoftAuthError.refreshFailed
        ) { complete in
            complete(.success("token"))
        }
        XCTAssertEqual(value, "token")
    }

    func testWaitSettlesWithTimeoutErrorWhenTheCallbackNeverArrives() async {
        do {
            let _: String = try await MicrosoftGraphCallbackWait.wait(
                timeout: 0.01,
                timeoutError: MicrosoftAuthError.refreshFailed
            ) { _ in }
            XCTFail("Expected refreshFailed")
        } catch {
            XCTAssertEqual(error as? MicrosoftAuthError, .refreshFailed)
        }
    }

    func testWaitIgnoresADuplicateCallback() async {
        do {
            let _: String = try await MicrosoftGraphCallbackWait.wait(
                timeout: nil,
                timeoutError: MicrosoftAuthError.refreshFailed
            ) { complete in
                complete(.failure(MicrosoftAuthError.cancelled))
                complete(.success("late"))
            }
            XCTFail("Expected the first result to win")
        } catch {
            XCTAssertEqual(error as? MicrosoftAuthError, .cancelled)
        }
    }

    func testLateSignOutDoesNotClearANewerSession() async {
        var session: String? = "old"
        await MicrosoftGraphSignOutFlow.run(
            clearLocalSession: { session = nil },
            finishSignOut: {
                // A newer sign-in completes while the old sign-out is pending.
                session = "new"
            }
        )
        XCTAssertEqual(session, "new")
    }
}
