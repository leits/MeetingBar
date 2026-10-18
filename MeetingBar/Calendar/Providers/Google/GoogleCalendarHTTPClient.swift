import Foundation

/// Runs Google Calendar list requests through the production status and pagination
/// policies. Only the network boundary and access-token source are replaceable.
/// The app passes URLSession and AppAuth; tests provide deterministic responses.
@MainActor
struct GoogleCalendarHTTPClient {
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    typealias AccessToken = @MainActor (_ forceRefresh: Bool) async throws -> String

    private let transport: Transport
    private let accessToken: AccessToken

    init(transport: @escaping Transport, accessToken: @escaping AccessToken) {
        self.transport = transport
        self.accessToken = accessToken
    }

    func fetchJSON(_ url: URL, calendarID: String? = nil) async throws -> [[String: Any]] {
        try await GoogleCalendarPagination.fetchAll(from: url) { pageURL in
            try await fetchJSONPage(pageURL, calendarID: calendarID)
        }
    }

    private func fetchJSONPage(
        _ url: URL,
        calendarID: String?,
        retrying: Bool = false
    ) async throws -> GoogleCalendarPage {
        let token = try await accessToken(false)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport(request)
        if let http = response as? HTTPURLResponse {
            switch GoogleHTTPStatusPolicy.classify(
                statusCode: http.statusCode,
                url: url,
                calendarID: calendarID,
                retrying: retrying
            ) {
            case .proceed:
                break
            case .retryWithForcedTokenRefresh:
                _ = try await accessToken(true)
                try Task.checkCancellation()
                return try await fetchJSONPage(url, calendarID: calendarID, retrying: true)
            case .throwAuthRequired:
                // A Calendar API rejection must not delete the persisted grant.
                throw AuthError.notSignedIn
            case let .throwError(error):
                throw error
            }
        }

        return try GoogleCalendarPage(data: data, url: url)
    }
}
