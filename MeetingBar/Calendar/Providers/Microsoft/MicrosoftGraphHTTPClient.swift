import Foundation

/// One page of a Graph collection response.
struct MicrosoftGraphPage {
    let items: [[String: Any]]
    let nextURL: URL?

    /// A page is usable only when it is complete: a missing `value` or an
    /// unusable `@odata.nextLink` must fail the fetch rather than be published
    /// as a shorter list, so last-known-good meetings survive.
    init(root: [String: Any], url: URL) throws {
        guard let items = root["value"] as? [[String: Any]] else {
            throw MicrosoftGraphError.malformedResponse(url)
        }
        self.items = items
        nextURL = MicrosoftGraphURLBuilder.nextLink(from: root)
        if nextURL == nil, root["@odata.nextLink"] != nil {
            throw MicrosoftGraphError.invalidPagination(url)
        }
    }
}

/// Runs Microsoft Graph collection requests through the production status and
/// pagination policies. Only the network boundary, access-token source and
/// retry delay are replaceable; the app passes URLSession and MSAL.
@MainActor
struct MicrosoftGraphHTTPClient {
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    typealias AccessToken = @MainActor (_ forceRefresh: Bool) async throws -> String
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void

    private let transport: Transport
    private let accessToken: AccessToken
    private let sleep: Sleep

    init(
        transport: @escaping Transport,
        accessToken: @escaping AccessToken,
        sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.transport = transport
        self.accessToken = accessToken
        self.sleep = sleep
    }

    /// Returns the items of every page, or throws: never a partial list.
    func fetchItems(_ url: URL, calendarID: String? = nil) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var pageURL = url
        var seenURLs: Set<URL> = [url]

        while true {
            try Task.checkCancellation()
            let page = try await fetchPage(pageURL, calendarID: calendarID)
            try Task.checkCancellation()
            items.append(contentsOf: page.items)
            guard let nextURL = page.nextURL else { return items }
            guard seenURLs.insert(nextURL).inserted else {
                throw MicrosoftGraphError.invalidPagination(url)
            }
            pageURL = nextURL
        }
    }

    private func fetchPage(
        _ url: URL,
        calendarID: String?,
        retrying: Bool = false,
        rateLimitRetries: Int = 0
    ) async throws -> MicrosoftGraphPage {
        let token = try await accessToken(false)

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            #"outlook.timezone="UTC", outlook.body-content-type="text""#,
            forHTTPHeaderField: "Prefer"
        )

        let (data, response) = try await transport(request)

        guard let http = response as? HTTPURLResponse else {
            throw MicrosoftGraphError.malformedResponse(url)
        }

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let graphErrorCode = (root?["error"] as? [String: Any])?["code"] as? String

        let decision = MicrosoftGraphHTTPStatusPolicy.classify(
            MicrosoftGraphResponse(
                statusCode: http.statusCode,
                url: url,
                calendarID: calendarID,
                graphErrorCode: graphErrorCode,
                retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After")
            ),
            retrying: retrying,
            rateLimitRetries: rateLimitRetries
        )
        switch decision {
        case .proceed:
            break
        case .retryWithForcedTokenRefresh:
            _ = try await accessToken(true)
            try Task.checkCancellation()
            return try await fetchPage(url, calendarID: calendarID, retrying: true, rateLimitRetries: rateLimitRetries)
        case .clearAuthAndThrowAuthRequired:
            throw MicrosoftAuthError.notSignedIn
        case let .retryAfterDelay(delay):
            try await sleep(delay)
            return try await fetchPage(url, calendarID: calendarID, retrying: retrying, rateLimitRetries: rateLimitRetries + 1)
        case let .throwError(error):
            throw error
        }

        guard let root else {
            throw MicrosoftGraphError.malformedResponse(url)
        }
        return try MicrosoftGraphPage(root: root, url: url)
    }
}
