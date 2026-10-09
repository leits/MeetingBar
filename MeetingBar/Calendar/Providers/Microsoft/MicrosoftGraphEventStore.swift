//
//  MicrosoftGraphEventStore.swift
//  MeetingBar
//
//  Microsoft 365 / Exchange Online calendar provider.
//
//  Authenticates with MSAL (Microsoft Authentication Library) against the
//  `common` authority so work, school, and personal Microsoft accounts can
//  sign in, then reads calendars and events through the Microsoft Graph REST
//  API. MSAL is used instead of a generic OIDC library so the app benefits
//  from the Microsoft Enterprise SSO plug-in on managed Macs, and so the
//  token lifecycle (Keychain-backed cache, silent refresh, revocation,
//  multiple accounts) stays inside the SDK: this store persists only the
//  opaque account identifier and never sees a refresh token.
//
//  The provider is an independent implementation that mirrors the shape of
//  `GCEventStore` (sign-in/refresh coalescing, a shared URLSession, per-call
//  HTTP classification, and a JSON → MBEvent parser) without sharing code
//  with it. Pure decisions live in `MicrosoftGraphPolicy.swift` so they can
//  be tested in the hostless logic package.
//

@preconcurrency import MSAL

import AppKit
import Defaults
import Foundation

/// Sendable projection of an MSAL result so no MSAL-typed value crosses an
/// isolation boundary out of the completion callback.
private struct MicrosoftTokenSnapshot: Sendable {
    let accessToken: String
    let expiresOn: Date?
    let accountIdentifier: String
    let username: String?
}

@MainActor
final class MicrosoftGraphEventStore: NSObject, AuthenticatedEventStore {
    // MARK: - Singleton

    static let shared = MicrosoftGraphEventStore()

    // MARK: - Constants

    private static let scopes = ["Calendars.Read"]
    /// Keychain service that remembers which MSAL account is signed in. The
    /// tokens themselves live in MSAL's own cache; this is only the account
    /// identifier so silent sign-in survives relaunch.
    private static let accountKeychainService = "\(AppInfo.bundleIdentifier).microsoft.accountIdentifier"
    /// Access token is treated as stale this many seconds before its real
    /// expiry so an in-flight request never races the deadline.
    private static let tokenFreshnessWindow: TimeInterval = 300
    /// Safety cap on `@odata.nextLink` following, per resource.
    private static let maxPages = 10

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = true
        // Bound each request so a stalled Graph call cannot hold a calendar
        // fetch open for URLSession's multi-day default resource timeout.
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    // MARK: - Stored state (MainActor-isolated)

    private var application: MSALPublicClientApplication?
    private var configuration: MicrosoftGraphConfiguration?
    private var accountIdentifier: String?
    private(set) var userEmail: String?

    private var cachedToken: MicrosoftTokenSnapshot?
    /// Set when silent refresh reports interaction is required. Sign-in is
    /// still possible (interactively), but background refresh cannot proceed.
    private var needsInteraction = false

    private var refreshTask: Task<String, Error>?
    /// Whether `refreshTask` was started with `forceRefresh`. A forced
    /// refresh (after a 401) must never reuse the result of a non-forced one,
    /// which may hand back the very token the server just rejected.
    private var refreshTaskIsForced = false
    private var presentationAnchor: MicrosoftAuthPresentationAnchor?
    /// Bumped whenever pending work is cancelled or the account is cleared, so
    /// a late MSAL callback cannot write credentials back after sign-out.
    private var operationGeneration = 0
    /// Set after an explicit sign-out so the next interactive sign-in offers
    /// the account picker instead of silently reusing the browser session.
    private var forceAccountSelectionOnNextInteractive = false

    override private init() {
        super.init()
        accountIdentifier = restoreAccountIdentifier()
    }

    // MARK: - Public state

    /// True only when MSAL still has a usable account. The persisted account
    /// identifier can outlive MSAL's own token cache (keychain reset,
    /// reinstall), so it is confirmed against MSAL rather than trusted alone,
    /// keeping the diagnostics report honest.
    var isAuthorized: Bool {
        guard !needsInteraction, accountIdentifier != nil else { return false }
        guard let application = try? makeApplication() else { return false }
        return (try? existingAccount(in: application)) != nil
    }

    /// Human-readable source of the resolved client ID for diagnostics
    /// ("build setting", "missing", or "invalid" when a client ID is present
    /// but malformed).
    var configurationSourceLabel: String {
        do {
            return try resolvedConfiguration().sourceLabel
        } catch {
            return "invalid"
        }
    }

    // MARK: - AuthenticatedEventStore

    /// Signs the user in, reusing the stored account silently when possible and otherwise running the interactive MSAL flow.
    func signIn(forcePrompt: Bool) async throws {
        let generation = operationGeneration
        let application = try makeApplication()

        if !forcePrompt, let account = try existingAccount(in: application) {
            do {
                let snapshot = try await acquireTokenSilent(application: application, account: account, forceRefresh: false)
                try applyIfCurrent(snapshot, generation: generation)
                return
            } catch let error as MicrosoftAuthError where error == .notSignedIn {
                // Silent path exhausted; fall through to interactive sign-in.
            }
        }

        let snapshot = try await acquireTokenInteractive(application: application, forcePrompt: forcePrompt)
        try applyIfCurrent(snapshot, generation: generation)
        AppMessageCenter.shared.post(.microsoftAccountConnected(email: snapshot.username ?? ""))
    }

    /// Signs out of MSAL and clears the persisted account identifier.
    func signOut() async {
        cancelPendingOperations()

        if let application = try? makeApplication(),
           let account = try? existingAccount(in: application) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let parameters = MSALSignoutParameters()
                parameters.signoutFromBrowser = false
                application.signout(with: account, signoutParameters: parameters) { _, _ in
                    continuation.resume()
                }
            }
            // Belt and suspenders: drop the local cache entry even if signout
            // reported an error.
            try? application.remove(account)
        }

        clearAccountState()
        forceAccountSelectionOnNextInteractive = true
    }

    /// Cancels in-flight refresh and interactive sign-in work and dismisses the sign-in window.
    func cancelPendingOperations() {
        operationGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        // Tell MSAL to end the system sign-in sheet as well; otherwise the
        // ASWebAuthenticationSession stays open and `acquireToken` never
        // completes, leaving the provider switch awaiting forever.
        _ = MSALPublicClientApplication.cancelCurrentWebAuthSession()
        presentationAnchor?.dismiss()
        presentationAnchor = nil
    }

    /// No-op: Microsoft Graph has no local source list to refresh.
    func refreshSources() async {}

    /// Fetches every calendar in the account, following Graph pagination.
    func fetchAllCalendars() async throws -> [MBCalendar] {
        try await ensureSignedIn()

        let email = userEmail
        var items: [[String: Any]] = []
        var url: URL? = try MicrosoftGraphURLBuilder.calendarsURL()
        var page = 0

        while let currentURL = url, page < Self.maxPages {
            let root = try await fetchJSON(currentURL)
            items.append(contentsOf: root["value"] as? [[String: Any]] ?? [])
            url = MicrosoftGraphURLBuilder.nextLink(from: root)
            page += 1
        }

        return items.compactMap { item -> MBCalendar? in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String else { return nil }
            let hexColor = item["hexColor"] as? String ?? ""
            let color = (hexColor.isEmpty || hexColor == "auto")
                ? NSColor.systemBlue
                : hexStringToUIColor(hex: hexColor)
            return MBCalendar(title: name, id: id, source: email, email: email, color: color)
        }
    }

    /// Fetches events for the selected calendars in the range, skipping calendars that are individually inaccessible.
    func fetchEventsForDateRange(
        for calendars: [MBCalendar],
        from: Date,
        to: Date
    ) async throws -> [MBEvent] {
        try await ensureSignedIn()

        var result: [MBEvent] = []
        var forbiddenErrors: [Error] = []
        var successfulCalendars = 0

        for calendar in calendars {
            do {
                let events = try await fetchEvents(for: calendar, from: from, to: to)
                successfulCalendars += 1
                result.append(contentsOf: events)
            } catch let error as MicrosoftGraphError {
                switch error {
                case .forbiddenCalendar, .mailboxNotAvailable:
                    MeetingBarLogger.calendar.warning(
                        "Skipping inaccessible Microsoft calendar \(calendar.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                    )
                    forbiddenErrors.append(error)
                default:
                    throw error
                }
            }
        }

        let deduplicated = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        return try MicrosoftGraphBatchPolicy.finish(
            events: Array(deduplicated),
            successfulCalendars: successfulCalendars,
            forbiddenErrors: forbiddenErrors
        )
    }

    // MARK: - Event fetching

    /// Fetches a single calendar's events for the range, following Graph pagination.
    private func fetchEvents(for calendar: MBCalendar, from: Date, to: Date) async throws -> [MBEvent] {
        let username = userEmail
        var events: [MBEvent] = []
        var url: URL? = try MicrosoftGraphURLBuilder.calendarViewURL(
            calendarID: calendar.id,
            start: from,
            end: to
        )
        var page = 0

        while let currentURL = url, page < Self.maxPages {
            let root = try await fetchJSON(currentURL, calendarID: calendar.id)
            let items = root["value"] as? [[String: Any]] ?? []
            events.append(contentsOf: items.compactMap {
                MSGraphParser.event(from: $0, calendar: calendar, username: username)
            })
            url = MicrosoftGraphURLBuilder.nextLink(from: root)
            page += 1
        }

        return events
    }

    // MARK: - Networking

    /// Performs an authorized Graph GET and applies the HTTP status policy (token refresh, throttling, per-calendar errors).
    private func fetchJSON(
        _ url: URL,
        calendarID: String? = nil,
        retrying: Bool = false,
        rateLimitRetries: Int = 0
    ) async throws -> [String: Any] {
        let token = try await validAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            #"outlook.timezone="UTC", outlook.body-content-type="text""#,
            forHTTPHeaderField: "Prefer"
        )

        let (data, response) = try await Self.session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MicrosoftGraphError.malformedResponse(url)
        }

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let graphErrorCode = (root?["error"] as? [String: Any])?["code"] as? String
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After")

        let classified = MicrosoftGraphHTTPStatusPolicy.classify(
            MicrosoftGraphResponse(
                statusCode: http.statusCode,
                url: url,
                calendarID: calendarID,
                graphErrorCode: graphErrorCode,
                retryAfterHeader: retryAfter
            ),
            retrying: retrying,
            rateLimitRetries: rateLimitRetries
        )
        switch classified {
        case .proceed:
            break
        case .retryWithForcedTokenRefresh:
            _ = try await validAccessToken(forceRefresh: true)
            return try await fetchJSON(url, calendarID: calendarID, retrying: true, rateLimitRetries: rateLimitRetries)
        case .clearAuthAndThrowAuthRequired:
            markNeedsInteraction()
            throw MicrosoftAuthError.notSignedIn
        case let .retryAfterDelay(delay):
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await fetchJSON(url, calendarID: calendarID, retrying: retrying, rateLimitRetries: rateLimitRetries + 1)
        case let .throwError(error):
            throw error
        }

        guard let root else {
            throw MicrosoftGraphError.malformedResponse(url)
        }
        return root
    }

    // MARK: - Sign-in helpers

    /// Ensures a valid access token without ever opening a browser. Fetching
    /// happens in the background (timer, relaunch), so an expired session must
    /// surface `.notSignedIn` and let the Reconnect UI drive interactive
    /// sign-in — never pop a sign-in window on its own.
    private func ensureSignedIn() async throws {
        _ = try await validAccessToken()
    }

    /// Returns a fresh access token, refreshing silently and coalescing concurrent refreshes.
    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh,
           let cachedToken,
           isTokenFresh(cachedToken) {
            return cachedToken.accessToken
        }

        if let running = refreshTask {
            if !forceRefresh || refreshTaskIsForced {
                return try await running.value
            }
            // Let the non-forced refresh settle, then run a forced one below.
            _ = try? await running.value
        }

        let generation = operationGeneration
        let task = Task<String, Error> { [self] in
            let application = try makeApplication()
            guard let account = try existingAccount(in: application) else {
                markNeedsInteraction()
                throw MicrosoftAuthError.notSignedIn
            }
            do {
                let snapshot = try await acquireTokenSilent(application: application, account: account, forceRefresh: forceRefresh)
                try applyIfCurrent(snapshot, generation: generation)
                return snapshot.accessToken
            } catch let error as MicrosoftAuthError where error == .notSignedIn {
                // Silent refresh needs interaction (refresh token revoked or
                // expired): record it so `isAuthorized` agrees with the
                // Reconnect UI.
                markNeedsInteraction()
                throw error
            }
        }
        refreshTask = task
        refreshTaskIsForced = forceRefresh
        // Only clear our own task: a newer one may have replaced it while we
        // were suspended (e.g. after cancelPendingOperations).
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value
    }

    /// Whether the cached token is still valid beyond the freshness window.
    private func isTokenFresh(_ snapshot: MicrosoftTokenSnapshot) -> Bool {
        guard let expiresOn = snapshot.expiresOn else { return false }
        return expiresOn > Date().addingTimeInterval(Self.tokenFreshnessWindow)
    }

    // MARK: - MSAL bridging

    /// Bridges MSAL's silent token acquisition into async/await as a Sendable snapshot.
    private func acquireTokenSilent(
        application: MSALPublicClientApplication,
        account: MSALAccount,
        forceRefresh: Bool
    ) async throws -> MicrosoftTokenSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let parameters = MSALSilentTokenParameters(scopes: Self.scopes, account: account)
            parameters.forceRefresh = forceRefresh
            application.acquireTokenSilent(with: parameters) { result, error in
                if let result {
                    once.resume(.success(Self.snapshot(from: result)))
                } else {
                    once.resume(.failure(Self.silentError(error)))
                }
            }
        }
    }

    /// Runs MSAL's interactive sign-in in the anchor window and returns a Sendable snapshot.
    private func acquireTokenInteractive(
        application: MSALPublicClientApplication,
        forcePrompt: Bool
    ) async throws -> MicrosoftTokenSnapshot {
        if let previous = presentationAnchor {
            // A second interactive attempt (e.g. Reconnect followed by Change
            // account) supersedes the first: end its web session so its
            // continuation resumes with `.cancelled` instead of leaking.
            _ = MSALPublicClientApplication.cancelCurrentWebAuthSession()
            previous.dismiss()
        }
        let anchor = MicrosoftAuthPresentationAnchor()
        presentationAnchor = anchor
        defer {
            anchor.dismiss()
            if presentationAnchor === anchor { presentationAnchor = nil }
        }

        let viewController = anchor.present { [weak self] in
            self?.cancelPendingOperations()
        }

        let loginHint = userEmail
        let selectAccount = forcePrompt || forceAccountSelectionOnNextInteractive
        forceAccountSelectionOnNextInteractive = false
        return try await withCheckedThrowingContinuation { continuation in
            // MSAL can invoke this completion more than once: after
            // `cancelCurrentWebAuthSession()` it reports the cancellation
            // immediately and the ASWebAuthenticationSession callback fires
            // again afterwards. Resuming a CheckedContinuation twice traps.
            let once = ResumeOnce(continuation)
            let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)
            webParameters.webviewType = .authenticationSession
            let parameters = MSALInteractiveTokenParameters(scopes: Self.scopes, webviewParameters: webParameters)
            parameters.promptType = selectAccount ? .selectAccount : .default
            parameters.loginHint = selectAccount ? nil : loginHint
            application.acquireToken(with: parameters) { result, error in
                if let result {
                    once.resume(.success(Self.snapshot(from: result)))
                } else {
                    once.resume(.failure(Self.interactiveError(error)))
                }
            }
        }
    }

    private nonisolated static func snapshot(from result: MSALResult) -> MicrosoftTokenSnapshot {
        MicrosoftTokenSnapshot(
            accessToken: result.accessToken,
            expiresOn: result.expiresOn,
            accountIdentifier: result.account.identifier ?? "",
            username: result.account.username
        )
    }

    /// Silent-path errors: interaction-required means the refresh token is
    /// gone/expired, which surfaces as `notSignedIn` so the Reconnect UI takes
    /// over. Everything else is a transient refresh failure.
    private nonisolated static func silentError(_ error: Error?) -> Error {
        guard let error else { return MicrosoftAuthError.refreshFailed }
        let nsError = error as NSError
        if nsError.domain == MSALErrorDomain, nsError.code == MSALError.interactionRequired.rawValue {
            return MicrosoftAuthError.notSignedIn
        }
        return readable(nsError)
    }

    private nonisolated static func interactiveError(_ error: Error?) -> Error {
        guard let error else { return MicrosoftAuthError.refreshFailed }
        let nsError = error as NSError
        if nsError.domain == MSALErrorDomain, nsError.code == MSALError.userCanceled.rawValue {
            return MicrosoftAuthError.cancelled
        }
        return readable(nsError)
    }

    /// MSAL populates `MSALErrorDescriptionKey` but not
    /// `NSLocalizedDescriptionKey`, so `localizedDescription` would read
    /// "MSALErrorDomain error -50000". Promote the real message so the status
    /// bar and Preferences show something actionable.
    private nonisolated static func readable(_ error: NSError) -> Error {
        guard error.domain == MSALErrorDomain,
              error.userInfo[NSLocalizedDescriptionKey] == nil,
              let description = error.userInfo[MSALErrorDescriptionKey] as? String,
              !description.isEmpty else {
            return error
        }
        var userInfo = error.userInfo
        userInfo[NSLocalizedDescriptionKey] = description
        return NSError(domain: error.domain, code: error.code, userInfo: userInfo)
    }

    /// Applies a freshly acquired token only if no cancellation or sign-out
    /// happened while it was in flight, so a late MSAL callback cannot restore
    /// credentials after the user signed out.
    private func applyIfCurrent(_ snapshot: MicrosoftTokenSnapshot, generation: Int) throws {
        guard generation == operationGeneration else { throw CancellationError() }
        apply(snapshot)
    }

    /// Stores the acquired token, email, and account identifier.
    private func apply(_ snapshot: MicrosoftTokenSnapshot) {
        cachedToken = snapshot
        needsInteraction = false
        if !snapshot.accountIdentifier.isEmpty {
            persist(accountIdentifier: snapshot.accountIdentifier)
        }
        if let username = snapshot.username {
            userEmail = username
        }
    }

    /// Marks that only interactive sign-in can recover, clearing the cached token.
    private func markNeedsInteraction() {
        needsInteraction = true
        cachedToken = nil
    }

    // MARK: - Configuration

    /// Builds (once) the MSAL application from the resolved configuration.
    private func makeApplication() throws -> MSALPublicClientApplication {
        if let application {
            return application
        }

        let configuration = try resolvedConfiguration()
        guard configuration.isConfigured else {
            throw MicrosoftAuthError.configurationMissing
        }

        let authority = try MSALAADAuthority(url: configuration.authorityURL)
        let config = MSALPublicClientApplicationConfig(
            clientId: configuration.clientID,
            redirectUri: configuration.redirectURI,
            authority: authority
        )
        // Store tokens in the app's own keychain access group so no
        // `keychain-access-groups` entitlement is required in the sandbox.
        config.cacheConfig.keychainSharingGroup = AppInfo.bundleIdentifier

        let application = try MSALPublicClientApplication(configuration: config)
        MeetingBarLogger.calendar.info(
            "Microsoft 365 provider configured from \(configuration.sourceLabel, privacy: .public)"
        )
        self.application = application
        self.configuration = configuration
        return application
    }

    /// Resolves and caches the Entra client configuration from the build setting.
    private func resolvedConfiguration() throws -> MicrosoftGraphConfiguration {
        if let configuration {
            return configuration
        }
        let buildClientID = Bundle.main.object(
            forInfoDictionaryKey: MicrosoftGraphConfigurationPolicy.buildClientIDKey
        ) as? String

        let configuration = try MicrosoftGraphConfigurationPolicy.resolve(
            buildClientID: buildClientID,
            bundleID: AppInfo.bundleIdentifier
        )
        self.configuration = configuration
        return configuration
    }

    /// Resolves the signed-in account strictly by the persisted identifier.
    /// It never falls back to `allAccounts().first`, which could silently pick
    /// a different identity when the MSAL cache holds several accounts.
    private func existingAccount(in application: MSALPublicClientApplication) throws -> MSALAccount? {
        guard let accountIdentifier else { return nil }
        do {
            return try application.account(forIdentifier: accountIdentifier)
        } catch let error as NSError where error.domain == MSALErrorDomain {
            throw error
        } catch {
            // `-accountForIdentifier:error:` returns nil with no NSError when
            // no cached account matches; Swift surfaces that as a generic
            // `_GenericObjCError.nilError`. Keychain OSStatus failures (cache
            // wiped, app re-signed with a different Team ID) land here too.
            // Either way the account cannot be used silently, so report "no
            // account" and let callers fall through to the Reconnect path.
            return nil
        }
    }

    // MARK: - Account identifier persistence

    /// Persists the signed-in account identifier to the keychain.
    private func persist(accountIdentifier: String) {
        self.accountIdentifier = accountIdentifier
        Keychain.save(data: Data(accountIdentifier.utf8), for: Self.accountKeychainService)
    }

    /// Restores the persisted account identifier from the keychain, if any.
    private func restoreAccountIdentifier() -> String? {
        guard let data = Keychain.load(for: Self.accountKeychainService) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Clears all local account state and bumps the operation generation.
    private func clearAccountState() {
        operationGeneration &+= 1
        accountIdentifier = nil
        userEmail = nil
        cachedToken = nil
        needsInteraction = false
        Keychain.delete(for: Self.accountKeychainService)
    }

    // MARK: - Graph JSON → MBEvent

    enum MSGraphParser {
        /// Builds an `MBEvent` from a Graph event JSON object, or nil when required fields are missing.
        static func event(
            from item: [String: Any],
            calendar: MBCalendar,
            username: String?
        ) -> MBEvent? {
            guard let eventID = item["id"] as? String else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Microsoft event without a string id"
                )
                return nil
            }

            guard let start = item["start"] as? [String: Any],
                  let end = item["end"] as? [String: Any] else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Microsoft event \(eventID, privacy: .private) without start/end"
                )
                return nil
            }

            let isAllDay = item["isAllDay"] as? Bool ?? false
            guard let startDate = date(from: start, isAllDay: isAllDay),
                  let endDate = date(from: end, isAllDay: isAllDay) else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Microsoft event \(eventID, privacy: .private) with unparseable dates"
                )
                return nil
            }

            let title = item["subject"] as? String
            let notes = (item["body"] as? [String: Any])?["content"] as? String
                ?? item["bodyPreview"] as? String
            let location = (item["location"] as? [String: Any])?["displayName"] as? String

            let statusValue = MicrosoftGraphEventMapping.status(
                isCancelled: item["isCancelled"] as? Bool ?? false,
                showAs: item["showAs"] as? String
            )

            let onlineMeeting = item["onlineMeeting"] as? [String: Any]
            let conferenceURL = MicrosoftGraphEventMapping.conferenceURL(
                onlineMeetingJoinURL: onlineMeeting?["joinUrl"] as? String,
                onlineMeetingURL: item["onlineMeetingUrl"] as? String
            )

            let calendarOpenURL = (item["webLink"] as? String).flatMap(URL.init(string:))
            let lastModifiedDate = (item["lastModifiedDateTime"] as? String)
                .flatMap { MicrosoftGraphDateParser.dateTime($0, timeZoneID: nil) }

            let organizerAddress = ((item["organizer"] as? [String: Any])?["emailAddress"]) as? [String: Any]
            let organizer = MBEventOrganizer(
                email: organizerAddress?["address"] as? String,
                name: organizerAddress?["name"] as? String
            )

            let attendees = parseAttendees(item: item, username: username)

            let recurrent = MicrosoftGraphEventMapping.isRecurrent(
                type: item["type"] as? String,
                seriesID: item["seriesMasterId"] as? String
            )

            return MBEvent(
                id: eventID,
                lastModifiedDate: lastModifiedDate,
                title: title,
                status: status(from: statusValue),
                notes: notes,
                location: location,
                url: nil,
                conferenceURL: conferenceURL,
                calendarOpenURL: calendarOpenURL,
                organizer: organizer,
                attendees: attendees,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                recurrent: recurrent,
                calendar: calendar,
                customRegexes: Defaults[.customRegexes]
            )
        }

        /// Maps Graph attendees to `MBEventAttendee`, synthesizing the current user from the event response status when absent.
        private static func parseAttendees(item: [String: Any], username: String?) -> [MBEventAttendee] {
            var attendees: [MBEventAttendee] = []
            var hasCurrentUser = false

            for raw in item["attendees"] as? [[String: Any]] ?? [] {
                let emailAddress = raw["emailAddress"] as? [String: Any]
                let address = emailAddress?["address"] as? String
                let name = emailAddress?["name"] as? String
                let responseStatus = (raw["status"] as? [String: Any])?["response"] as? String
                let isCurrentUser = MicrosoftGraphEventMapping.isCurrentUser(address: address, username: username)
                if isCurrentUser { hasCurrentUser = true }

                attendees.append(MBEventAttendee(
                    email: address,
                    name: name,
                    status: attendeeStatus(from: MicrosoftGraphEventMapping.attendeeStatus(response: responseStatus)),
                    optional: MicrosoftGraphEventMapping.isOptional(attendeeType: raw["type"] as? String),
                    isCurrentUser: isCurrentUser
                ))
            }

            // Graph often omits the signed-in user from `attendees` (e.g. when
            // they are the organizer). `MBEvent.participationStatus` is derived
            // from the attendee flagged `isCurrentUser`, so synthesize one from
            // the event-level responseStatus to keep declined/pending filtering
            // working.
            if !hasCurrentUser, let username {
                let response = (item["responseStatus"] as? [String: Any])?["response"] as? String
                attendees.append(MBEventAttendee(
                    email: username,
                    name: nil,
                    status: attendeeStatus(from: MicrosoftGraphEventMapping.attendeeStatus(response: response)),
                    optional: false,
                    isCurrentUser: true
                ))
            }

            return attendees
        }

        /// Parses a Graph date value, using local midnight for all-day events.
        private static func date(from value: [String: Any], isAllDay: Bool) -> Date? {
            guard let dateTime = value["dateTime"] as? String else { return nil }
            if isAllDay {
                return MicrosoftGraphDateParser.allDayLocalDate(dateTime)
            }
            return MicrosoftGraphDateParser.dateTime(dateTime, timeZoneID: value["timeZone"] as? String)
        }

        /// Maps the policy's event-status value to `MBEventStatus`.
        private static func status(from value: MicrosoftGraphEventStatusValue) -> MBEventStatus {
            switch value {
            case .confirmed: return .confirmed
            case .tentative: return .tentative
            case .canceled: return .canceled
            }
        }

        /// Maps the policy's response value to `MBEventAttendeeStatus`.
        private static func attendeeStatus(from value: MicrosoftGraphResponseValue) -> MBEventAttendeeStatus {
            switch value {
            case .accepted: return .accepted
            case .declined: return .declined
            case .tentative: return .tentative
            case .pending: return .pending
            case .unknown: return .unknown
            }
        }
    }
}

/// Resumes a `CheckedContinuation` at most once. MSAL completion blocks are
/// not guaranteed to fire exactly once (see `acquireTokenInteractive`), and a
/// second resume would trap the process.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
