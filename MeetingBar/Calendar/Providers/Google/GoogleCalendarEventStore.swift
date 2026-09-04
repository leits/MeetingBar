//
//  GCEventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 21.11.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import AppAuthCore
import AppKit
import Defaults
import Foundation

let googleClientNumber = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_NUMBER") as! String
let googleClientSecret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as! String
let googleAuthKeychainName = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_AUTH_KEYCHAIN_NAME") as! String

extension OIDServiceConfiguration: @unchecked @retroactive Sendable {}

extension OIDAuthState {
    /// token is considered fresh if it expires later than 300 seconds from now
    var isTokenFresh: Bool {
        guard let exp = lastTokenResponse?.accessTokenExpirationDate else { return false }
        return exp > Date().addingTimeInterval(300)
    }

    /// convenience email extraction from ID token
    var userEmail: String? {
        guard let idToken = lastTokenResponse?.idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count > 1,
              let payloadData = Data(base64Encoded: String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }
}

// MARK: - GCEventStore
@MainActor
final class GCEventStore: NSObject,
                           AuthenticatedEventStore,
                           @preconcurrency OIDExternalUserAgent,
                          @preconcurrency OIDAuthStateChangeDelegate,
                          @preconcurrency OIDAuthStateErrorDelegate {

    // MARK: Static constants
    private static let kIssuer       = "https://accounts.google.com"
    private static let kClientID     = "\(googleClientNumber).apps.googleusercontent.com"
    private static let kClientSecret = googleClientSecret
    private static let kRedirectURI  = "com.googleusercontent.apps.\(googleClientNumber):/oauthredirect"
    private static let kKeychainName = googleAuthKeychainName

    // MARK: Stored properties
    @MainActor var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private(set) var userEmail: String?

    private var authState: OIDAuthState? {
        didSet {
            // ensure delegates always set
            authState?.stateChangeDelegate = self
            authState?.errorDelegate       = self
            persistAuthState()
        }
    }

    private var refreshTask: Task<String, Error>?
    /// Identifies which task currently owns `refreshTask`. A forced refresh
    /// replaces the slot while an ordinary refresh may still be running, and
    /// without this the finishing ordinary task would clear the slot out from
    /// under its replacement — losing the handle `cancelPendingOperations` needs
    /// and letting the next caller start a third refresh instead of joining.
    private var refreshTaskGeneration = 0
    /// Upper bound on one AppAuth token refresh.
    ///
    /// AppAuth issues token requests on `OIDURLSessionProvider.session`, which
    /// defaults to `URLSession.shared` — *not* the hardened session below, so
    /// none of its configuration applies to the refresh path. `URLSession`'s
    /// own 60s default request timeout still bounds that call, so this deadline
    /// sits beyond it and fires only when the callback never arrives at all.
    private static let tokenRefreshTimeout: TimeInterval = 90

    // Shared URLSession to leverage connection reuse
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 6
        // Every request must fail within a bounded time so the next refresh
        // cycle can retry. `waitsForConnectivity` suppresses
        // `timeoutIntervalForRequest` entirely and lets a request issued while
        // offline (wake from sleep before Wi-Fi/VPN is up) park for
        // `timeoutIntervalForResource` — seven days by default. That is not a
        // slow refresh, it is a refresh that never reports back, which leaves
        // the menu bar showing yesterday's events indefinitely.
        cfg.waitsForConnectivity          = false
        cfg.timeoutIntervalForRequest     = 30
        cfg.timeoutIntervalForResource    = 90
        return URLSession(configuration: cfg)
    }()
    private var urlSession: URLSession { Self.session }

    // Singleton
    static let shared = GCEventStore()
    private override init() {
        super.init()
        self.authState = restoreAuthState()
        // delegates were set in didSet, but set them again just in case restore returned nil
        self.authState?.stateChangeDelegate = self
        self.authState?.errorDelegate       = self
    }

    // MARK: Public API

    var isAuthorized: Bool { authState?.isAuthorized == true }

    func signIn(forcePrompt: Bool = false) async throws {
        if Self.shouldSkipSignIn(forcePrompt: forcePrompt, state: authState) {
            return
        }

        try await performAuthorization(forcePrompt: forcePrompt)

        // Google only issues a refresh token when the user actually walks
        // through the consent screen. An account that still holds a grant from
        // a previous install authorizes silently and returns none, which leaves
        // `hasReusableSession` false forever: no unattended refresh can run, and
        // because the provider switch fails before the active provider is set,
        // Preferences hides the Reconnect button that would otherwise recover.
        // Re-run the flow once demanding consent so the refresh token comes back.
        guard !forcePrompt, authState?.refreshToken == nil else { return }
        MeetingBarLogger.calendar.warning(
            "Google authorization returned no refresh token; retrying with forced consent"
        )
        try await performAuthorization(forcePrompt: true)
    }

    private func performAuthorization(forcePrompt: Bool) async throws {
        // discover configuration for Google issuer
        let config = try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.discoverConfiguration(forIssuer: URL(string: Self.kIssuer)!) { cfg, err in
                if let cfg { cont.resume(returning: cfg) } else { cont.resume(throwing: err ?? NSError(domain: "GoogleSignIn", code: -1)) }
            }
        }

        // request scopes we need
        let scopes = [
            "email",
            "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
            "https://www.googleapis.com/auth/calendar.events.readonly"
        ]

        // additional parameters to be sure we get refresh_token
        var extra = [
            "access_type": "offline"
        ]
        if forcePrompt {
            extra["prompt"] = "consent"
        }

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: Self.kClientID,
            clientSecret: Self.kClientSecret,
            scopes: scopes,
            redirectURL: URL(string: Self.kRedirectURI)!,
            responseType: OIDResponseTypeCode,
            additionalParameters: extra
        )

        try await withCheckedThrowingContinuation { cont in
            self.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request,
                                                                   externalUserAgent: self) { [weak self] state, error in
                guard let self else { return }
                if let state {
                    self.authState = state    // didSet handles persistence & delegates
                    self.userEmail = state.userEmail
                    AppMessageCenter.shared.post(
                        .googleAccountConnected(email: self.userEmail ?? "")
                    )
                    cont.resume()
                } else {
                    cont.resume(throwing: Self.authorizationError(error))
                }
            }
        }
    }

    private static func authorizationError(_ error: Error?) -> Error {
        guard let error else {
            return NSError(domain: "GoogleSignIn", code: 1)
        }

        let nsError = error as NSError
        let cancellationCodes = [-3, -4]
        if nsError.domain == OIDGeneralErrorDomain,
           cancellationCodes.contains(nsError.code) {
            return AuthError.cancelled
        }
        return error
    }

    func signOut() async {
        cancelPendingOperations()
        guard let state = authState else { return }

        // Revoke tokens in parallel
        let access  = state.lastTokenResponse?.accessToken
        let refresh = state.refreshToken
        await withTaskGroup(of: Void.self) { grp in
            if let acc = access { grp.addTask { try? await self.revoke(token: acc) } }
            if let ref = refresh { grp.addTask { try? await self.revoke(token: ref) } }
        }

        clearAuthState()
    }

    func cancelPendingOperations() {
        refreshTask?.cancel()
        refreshTask = nil

        let flow = currentAuthorizationFlow
        currentAuthorizationFlow = nil
        flow?.cancel()
    }

    func refreshSources() async {}

    func fetchAllCalendars() async throws -> [MBCalendar] {
        try requireReusableSession()

        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true")!
        let items = try await fetchJSON(url)

        return items.compactMap { item -> MBCalendar? in
            guard let title = item["summary"] as? String,
                  let calendarID = item["id"] as? String,
                  let backgroundColor = item["backgroundColor"] as? String else { return nil }

            return MBCalendar(title: title,
                              id: calendarID,
                              source: userEmail,
                              email: userEmail,
                              color: hexStringToUIColor(hex: backgroundColor))
        }
    }

    private func getCalendarEventsForDateRange(calendar: MBCalendar,
                                               dateFrom: Date,
                                               dateTo: Date) async throws -> [MBEvent] {
        let iso = ISO8601DateFormatter()
        let timeMin = iso.string(from: dateFrom)
        let timeMax = iso.string(from: dateTo)
        let url = try Self.eventsURL(
            calendarID: calendar.id,
            timeMin: timeMin,
            timeMax: timeMax
        )

        let items = try await fetchJSON(url, calendarID: calendar.id)
        return items.compactMap { GCParser.event(from: $0, calendar: calendar) }
    }

    static func eventsURL(calendarID: String, timeMin: String, timeMax: String) throws -> URL {
        // Calendar IDs can contain `#`, `@`, `+`, and group-address punctuation.
        // Path interpolation without escaping breaks for those calendars
        // (Google returns 404). Build the path via `URLComponents.path` so
        // encoding happens once, correctly.
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.googleapis.com"
        comps.path = "/calendar/v3/calendars/\(calendarID)/events"
        comps.queryItems = [
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "eventTypes", value: "default"),
            .init(name: "timeMax", value: timeMax),
            .init(name: "timeMin", value: timeMin)
        ]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }

        return url
    }

    func fetchEventsForDateRange(for calendars: [MBCalendar],
                                 from: Date,
                                 to: Date) async throws -> [MBEvent] {
        try requireReusableSession()
        var result: [MBEvent] = []
        var forbiddenErrors: [Error] = []
        var successfulCalendars = 0
        for cal in calendars {
            do {
                let ev = try await getCalendarEventsForDateRange(calendar: cal, dateFrom: from, dateTo: to)
                successfulCalendars += 1
                result.append(contentsOf: ev)
            } catch let error as GoogleCalendarError {
                switch error {
                case .forbiddenCalendar:
                    MeetingBarLogger.calendar.warning(
                        "Skipping inaccessible Google calendar \(cal.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                    )
                    forbiddenErrors.append(error)
                default:
                    throw error
                }
            } catch {
                throw error
            }
        }
        return try GoogleCalendarBatchPolicy.finish(
            events: result.deduplicatedPreferringResolvedAttendee(),
            successfulCalendars: successfulCalendars,
            forbiddenErrors: forbiddenErrors
        )
    }

    // MARK: - Private helpers

    /// Gate for fetches, which always originate from an unattended refresh
    /// cycle (timer, wake, day change) rather than from a user gesture.
    ///
    /// This deliberately never starts an interactive sign-in. Doing so from a
    /// background refresh opened a browser tab nobody was watching and then
    /// awaited its callback forever, so the refresh never completed and every
    /// later one queued behind it. Interactive authorization belongs to the
    /// explicit `signIn(forcePrompt:)` entry point that provider selection and
    /// the Reconnect button call; here we surface "reconnect required" and let
    /// the user act on it.
    private func requireReusableSession() throws {
        guard Self.hasReusableSession(authState) else {
            throw AuthError.notSignedIn
        }
    }

    nonisolated static func hasReusableSession(_ state: OIDAuthState?) -> Bool {
        state?.isAuthorized == true && state?.refreshToken != nil
    }

    nonisolated static func shouldSkipSignIn(
        forcePrompt: Bool,
        state: OIDAuthState?
    ) -> Bool {
        !forcePrompt && hasReusableSession(state)
    }

    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let state = authState else { throw AuthError.notSignedIn }

        if !forceRefresh,
           state.isTokenFresh,
           let token = state.lastTokenResponse?.accessToken {
            return token
        }

        // A forced refresh is only ever requested because the token we just
        // used was rejected, so it must not be answered by an in-flight
        // ordinary refresh — that task can only hand back the same bad token.
        if !forceRefresh, let running = refreshTask { return try await running.value }

        refreshTaskGeneration += 1
        let generation = refreshTaskGeneration
        let task = Task<String, Error> {
            defer { if refreshTaskGeneration == generation { refreshTask = nil } }
            return try await withCheckedThrowingContinuation { cont in
                // `performAction` owns its URLSession task internally and offers
                // no way to cancel it, and this is an unstructured Task, so
                // cancelling whoever awaits it does not reach in here. A
                // continuation that AppAuth never resumes would therefore
                // outlive every timeout the refresh cycle can apply and strand
                // the serialized pipeline — the exact failure this change set
                // exists to remove. Settle the wait on our own deadline instead
                // and let a late callback find the resume already claimed.
                let resumeGuard = SingleResumeGuard()
                let deadline = Task {
                    try? await Task.sleep(
                        nanoseconds: UInt64(Self.tokenRefreshTimeout * Double(NSEC_PER_SEC))
                    )
                    guard !Task.isCancelled, resumeGuard.claim() else { return }
                    MeetingBarLogger.calendar.error(
                        "Google token refresh did not return within \(Int(Self.tokenRefreshTimeout))s"
                    )
                    self.discardStuckAuthState()
                    cont.resume(
                        throwing: AuthError.temporarilyUnavailable(
                            underlying: URLError(.timedOut)
                        )
                    )
                }

                if forceRefresh { state.setNeedsTokenRefresh() }

                state.performAction { accessToken, _, error in
                    guard resumeGuard.claim() else { return }
                    deadline.cancel()
                    // `error` must be inspected before `accessToken`. When the
                    // token endpoint is unreachable, AppAuth reports the failure
                    // as a transient error but still passes back the *previous*,
                    // already-expired access token (OIDAuthState only nils it out
                    // once the grant itself is rejected). Treating that as a
                    // success sends a known-expired token to Google, which
                    // answers 401 → forced refresh → 401 again → "sign the user
                    // out", so a few seconds without network destroyed the
                    // stored refresh token and forced a full re-consent.
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == OIDOAuthTokenErrorDomain {
                            // Google rejected the refresh token itself. Clearing
                            // the session is handled by the errorDelegate.
                            cont.resume(throwing: AuthError.notSignedIn)
                        } else {
                            cont.resume(
                                throwing: AuthError.temporarilyUnavailable(underlying: error)
                            )
                        }
                        return
                    }

                    if let token = accessToken {
                        cont.resume(returning: token) // stateChangeDelegate persists new tokens
                    } else {
                        cont.resume(throwing: AuthError.refreshFailed)
                    }
                }
            }
        }

        refreshTask = task
        return try await task.value
    }

    // MARK: Keychain persistence

    private func persistAuthState() {
        guard let state = authState else {
            Keychain.delete(for: Self.kKeychainName)
            return
        }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
            Keychain.save(data: data, for: Self.kKeychainName)
        } catch {
            let errorDescription = String(describing: error)
            MeetingBarLogger.calendar.error(
                "Could not archive Google auth state: \(errorDescription, privacy: .private)"
            )
        }
    }

    private func restoreAuthState() -> OIDAuthState? {
        guard let data = Keychain.load(for: Self.kKeychainName) else { return nil }
        do {
            guard let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) else { return nil }
            userEmail = state.userEmail
            return state
        } catch {
            let errorDescription = String(describing: error)
            MeetingBarLogger.calendar.error(
                "Could not restore Google auth state: \(errorDescription, privacy: .private)"
            )
            return nil
        }
    }

    /// Replaces the `OIDAuthState` whose token request never came back.
    ///
    /// AppAuth serializes refreshes through `_pendingActions`, which only that
    /// request's own callback clears. A request that never completes therefore
    /// parks every later refresh behind it for the lifetime of the state
    /// object: each one enqueues, is never called back, and waits out its own
    /// deadline. Timing out alone would only downgrade the failure from hanging
    /// once to failing slowly forever. Rebuilding from the persisted session
    /// leaves the stuck queue behind while keeping the user signed in.
    private func discardStuckAuthState() {
        guard let restored = restoreAuthState() else { return }
        authState = restored
    }

    private func clearAuthState() {
        authState  = nil
        userEmail  = nil
        Keychain.delete(for: Self.kKeychainName)
    }

    // MARK: Networking helper
    private func fetchJSON(_ url: URL, calendarID: String? = nil, retrying: Bool = false) async throws -> [[String: Any]] {
        let token = try await validAccessToken()

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)

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
                _ = try await validAccessToken(forceRefresh: true)
                return try await fetchJSON(url, calendarID: calendarID, retrying: true)
            case .throwAuthRequired:
                // Deliberately keeps the stored session. A 401 from the
                // Calendar API only proves this access token was refused, and
                // a proxy or captive portal can produce one against a healthy
                // grant. The session is discarded only when the token endpoint
                // rejects the refresh token, via the errorDelegate below.
                throw AuthError.notSignedIn
            case let .throwError(error):
                throw error
            }
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let items = root["items"] as? [[String: Any]] else {
            throw GoogleCalendarError.missingItems(url)
        }
        return items
    }

    private func revoke(token: String) async throws {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("token=\(token)".utf8)

        let (_, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "GoogleRevoke", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // MARK: - OIDAuthState Delegates
    func didChange(_ state: OIDAuthState) {
        // persist every change (e.g., refreshed token)
        persistAuthState()
    }

    func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        let nsErr = error as NSError
        if nsErr.domain == OIDOAuthTokenErrorDomain {
            // refresh token invalid → clean state & notify
            clearAuthState()
        }
    }

    // MARK: - OIDExternalUserAgent
    func present(_ request: OIDExternalUserAgentRequest, session _: OIDExternalUserAgentSession) -> Bool {
        if let url = request.externalUserAgentRequestURL(), NSWorkspace.shared.open(url) {
            return true
        }
        return false
    }

    func dismiss(animated _: Bool, completion: @escaping () -> Void) { completion() }

    // MARK: - Google JSON ➜ MBEvent converter
    enum GCParser {
        // swiftlint:disable:next cyclomatic_complexity
        static func event(from item: [String: Any],
                          calendar: MBCalendar) -> MBEvent? {
            guard let eventID = item["id"] as? String else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Google Calendar event without a string id"
                )
                return nil
            }

            let formatter = ISO8601DateFormatter()
            let lastModifiedDate = formatter.date(from: item["updated"] as? String ?? "")
            let title = item["summary"] as? String
            var status: MBEventStatus
            switch item["status"] as? String {
            case "confirmed":
                status = .confirmed
            case "tentative":
                status = .tentative
            case "cancelled":
                status = .canceled
            default:
                status = .none
            }

            let notes = item["description"] as? String
            let location = item["location"] as? String

            // Google Calendar exposes the meeting URL through structured
            // conferenceData. Surface it as `conferenceURL` so the link
            // detector can score it ahead of any URL accidentally pasted
            // into notes (#847). The plain `url` field remains nil for
            // Google events — Google Calendar has no per-event "user URL"
            // equivalent of EKEvent.url.
            var conferenceURL: URL?
            if let conferenceData = item["conferenceData"] as? [String: Any],
               let entryPoints = conferenceData["entryPoints"] as? [[String: Any]],
               let videoEntryPoint = entryPoints.first(where: { $0["entryPointType"] as? String == "video" }) {
                conferenceURL = (videoEntryPoint["uri"] as? String).flatMap(URL.init(string:))
            }

            let organizerRaw = item["organizer"] as? [String: Any]
            let organizer = MBEventOrganizer(email: organizerRaw?["email"] as? String, name: organizerRaw?["name"] as? String)

            var attendees: [MBEventAttendee] = []
            let rawAttendees = item["attendees"] as? [[String: Any]] ?? []
            for jsonAttendee in rawAttendees {
                let email = jsonAttendee["email"] as? String
                let name = jsonAttendee["displayName"] as? String
                let optional = jsonAttendee["optional"] as? Bool ?? false
                let isCurrentUser = jsonAttendee["self"] as? Bool ?? false

                var attendeeStatus: MBEventAttendeeStatus
                switch jsonAttendee["responseStatus"] as? String {
                case "accepted":
                    attendeeStatus = .accepted
                case "declined":
                    attendeeStatus = .declined
                case "tentative":
                    attendeeStatus = .tentative
                case "needsAction":
                    attendeeStatus = .pending
                default:
                    attendeeStatus = .unknown
                }
                let attendee = MBEventAttendee(email: email, name: name, status: attendeeStatus, optional: optional, isCurrentUser: isCurrentUser)
                attendees.append(attendee)
            }

            var startDate: Date
            var endDate: Date
            var isAllDay: Bool

            guard let itemStart = item["start"] as? [String: String],
                  let itemEnd = item["end"] as? [String: String] else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Google event \(eventID, privacy: .private) without valid start/end dictionaries"
                )
                return nil
            }

            if let startDateTime = itemStart["dateTime"], let endDateTime = itemEnd["dateTime"] {
                let formatter = ISO8601DateFormatter()
                guard let parsedStartDate = formatter.date(from: startDateTime),
                      let parsedEndDate = formatter.date(from: endDateTime) else {
                    MeetingBarLogger.calendar.warning(
                        "Skipping Google event \(eventID, privacy: .private) with invalid dateTime values"
                    )
                    return nil
                }
                startDate = parsedStartDate
                endDate = parsedEndDate
                isAllDay = false
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                guard let startDateString = itemStart["date"],
                      let endDateString = itemEnd["date"],
                      let parsedStartDate = formatter.date(from: startDateString),
                      let parsedEndDate = formatter.date(from: endDateString) else {
                    MeetingBarLogger.calendar.warning(
                        "Skipping Google event \(eventID, privacy: .private) with invalid all-day date values"
                    )
                    return nil
                }
                startDate = parsedStartDate
                endDate = parsedEndDate
                isAllDay = true
            }

            let recurrent = (item["recurringEventId"] != nil) ? true : false

            // Web link to the event in Google Calendar; used for "Open in
            // Calendar" since `ical://ekevent/<google-id>` is not valid.
            let calendarOpenURL = (item["htmlLink"] as? String).flatMap(URL.init(string:))

            return MBEvent(
                id: eventID,
                lastModifiedDate: lastModifiedDate,
                title: title,
                status: status,
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
    }
}
