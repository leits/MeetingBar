import Foundation

struct GoogleCalendarPage {
    let items: [[String: Any]]
    let nextPageToken: String?

    init(items: [[String: Any]], nextPageToken: String? = nil) {
        self.items = items
        self.nextPageToken = nextPageToken
    }

    init(data: Data, url: URL) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleCalendarError.missingItems(url)
        }
        if let items = root["items"] as? [[String: Any]] {
            self.items = items
        } else if root["items"] == nil,
                  let kind = root["kind"] as? String,
                  ["calendar#calendarList", "calendar#events"].contains(kind) {
            // Google may omit the items field on a valid empty list page.
            self.items = []
        } else {
            throw GoogleCalendarError.missingItems(url)
        }
        if let value = root["nextPageToken"] {
            guard let token = value as? String else {
                throw GoogleCalendarError.invalidPagination(url)
            }
            nextPageToken = token.isEmpty ? nil : token
        } else {
            nextPageToken = nil
        }
    }
}

/// Page data stays on the Google store's actor because its existing JSON
/// dictionaries contain `Any`. No unchecked Sendable conformance is needed.
@MainActor
enum GoogleCalendarPagination {
    static func fetchAll(
        from url: URL,
        fetchPage: @MainActor (URL) async throws -> GoogleCalendarPage
    ) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var pageURL = url
        var seenTokens = Set<String>()
        if let initialToken = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "pageToken" })?.value {
            seenTokens.insert(initialToken)
        }

        while true {
            try Task.checkCancellation()
            let page = try await fetchPage(pageURL)
            try Task.checkCancellation()
            items.append(contentsOf: page.items)
            guard let token = page.nextPageToken, !token.isEmpty else { return items }
            guard seenTokens.insert(token).inserted else {
                throw GoogleCalendarError.invalidPagination(url)
            }
            pageURL = try self.url(for: url, pageToken: token)
        }
    }

    static func url(for originalURL: URL, pageToken: String) throws -> URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false),
              let encodedToken = pageToken.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw URLError(.badURL)
        }
        // Preserve the original encoded query, especially the event time range.
        // Encode '+' in opaque tokens as %2B rather than form-query whitespace.
        var query = components.percentEncodedQueryItems ?? []
        query.removeAll { $0.name == "pageToken" }
        query.append(URLQueryItem(name: "pageToken", value: encodedToken))
        components.percentEncodedQueryItems = query
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}
