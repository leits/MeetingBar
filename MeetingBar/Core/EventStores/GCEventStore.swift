//
//  GCEventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 21.11.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import AppAuthCore
import AppKit
import Foundation

let googleClientNumber = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_NUMBER") as! String
let googleClientSecret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as! String
let googleAuthKeychainName = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_AUTH_KEYCHAIN_NAME") as! String

extension OIDServiceConfiguration: @unchecked @retroactive Sendable {}

enum AuthError: Error {
    case notSignedIn
    case refreshFailed
}

extension OIDAuthState {
    /// token is considered fresh if it expires later than 30 seconds from now
    var isTokenFresh: Bool {
        guard let exp = lastTokenResponse?.accessTokenExpirationDate else { return false }
        return exp > Date().addingTimeInterval(30)
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
                           EventStore,
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

    private var signInTask: Task<Void, Error>?
    private var refreshTask: Task<String, Error>?

    // Shared URLSession to leverage connection reuse
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.waitsForConnectivity          = true
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

    func signIn() async throws {
        // if already authorised, nothing to do
        if authState?.isAuthorized == true { return }

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
        let extra = [
            "access_type": "offline",
            "prompt": "consent"
        ]

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
                    sendNotification("Google Account connected", "\(self.userEmail ?? "") is connected")
                    cont.resume()
                } else {
                    cont.resume(throwing: error ?? NSError(domain: "GoogleSignIn", code: 1))
                }
            }
        }
    }

    func signOut() async {
        guard let state = authState else { return }

        if let flow = currentAuthorizationFlow {
                currentAuthorizationFlow = nil
                await MainActor.run { flow.cancel() }
            } else {
                currentAuthorizationFlow = nil
            }

        // Revoke tokens in parallel
        let access  = state.lastTokenResponse?.accessToken
        let refresh = state.lastTokenResponse?.refreshToken
        await withTaskGroup(of: Void.self) { grp in
            if let acc = access { grp.addTask { try? await self.revoke(token: acc) } }
            if let ref = refresh { grp.addTask { try? await self.revoke(token: ref) } }
        }

        urlSession.invalidateAndCancel()

        clearAuthState()
    }

    func refreshSources() async {}

    func fetchAllCalendars() async throws -> [MBCalendar] {
        try await ensureSignedIn()

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

        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendar.id)/events")!
        comps.queryItems = [
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "eventTypes", value: "default"),
            .init(name: "timeMax", value: timeMax),
            .init(name: "timeMin", value: timeMin)
        ]

        let items = try await fetchJSON(comps.url!)
        return items.compactMap { GCParser.event(from: $0, calendar: calendar) }
    }

    func fetchEventsForDateRange(for calendars: [MBCalendar],
                                 from: Date,
                                 to: Date) async throws -> [MBEvent] {
        try await ensureSignedIn()
        var result: [MBEvent] = []
        for cal in calendars {
            let ev = try await getCalendarEventsForDateRange(calendar: cal, dateFrom: from, dateTo: to)
            result.append(contentsOf: ev)
        }
        return result
    }

    // MARK: - Private helpers
    private func ensureSignedIn() async throws {
        if authState?.isAuthorized == true { return }

        if let running = signInTask { return try await running.value }

        let task = Task {
            try await signIn()
        }
        signInTask = task
        try await task.value
        signInTask = nil
    }

    private func validAccessToken() async throws -> String {
        guard let state = authState else { throw AuthError.notSignedIn }

        // fresh token? -> return
        if state.isTokenFresh, let token = state.lastTokenResponse?.accessToken { return token }

        // існує task refresh
        if let running = refreshTask { return try await running.value }

        let task = Task<String, Error> {
            defer { refreshTask = nil }
            return try await withCheckedThrowingContinuation { cont in
                state.performAction { [weak self] accessToken, _, error in
                    guard let self else { return }
                    if let token = accessToken {
                        cont.resume(returning: token) // stateChangeDelegate persists new tokens
                    } else if let err = error as NSError? {
                        // only treat OAuth domain errors as fatal
                        if err.domain == OIDOAuthTokenErrorDomain {
                            self.clearAuthState()
                        }
                        cont.resume(throwing: err)
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
            NSLog("Error archiving OIDAuthState: \(error)")
        }
    }

    private func restoreAuthState() -> OIDAuthState? {
        guard let data = Keychain.load(for: Self.kKeychainName) else { return nil }
        do {
            guard let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) else { return nil }
            userEmail = state.userEmail
            return state
        } catch {
            NSLog("Error unarchiving OIDAuthState: \(error)")
            return nil
        }
    }

    private func clearAuthState() {
        authState  = nil
        userEmail  = nil
        Keychain.delete(for: Self.kKeychainName)
    }

    // MARK: Networking helper
    private func fetchJSON(_ url: URL) async throws -> [[String: Any]] {
        let token = try await validAccessToken()

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 401, 403:
                // refresh token revoked – force re‑login
                clearAuthState()
                throw AuthError.notSignedIn
            case 200...299:
                break
            default:
                throw NSError(domain: "HTTP", code: http.statusCode)
            }
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return root["items"] as! [[String: Any]]
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
        static func event(from item: [String: Any],
                          calendar: MBCalendar) -> MBEvent? {
            let eventID = item["id"] as! String

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

            var url: URL?
            if let conferenceData = item["conferenceData"] as? [String: Any] {
                if let entryPoints = conferenceData["entryPoints"] as? [[String: String]] {
                    if let videoEntryPoint = entryPoints.first(where: { $0["entryPointType"] == "video" }) {
                        url = URL(string: videoEntryPoint["uri"] ?? "")
                    }
                }
            }

            let organizerRaw = item["organizer"] as? [String: String]
            let organizer = MBEventOrganizer(email: organizerRaw?["email"], name: organizerRaw?["name"])

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

            let itemStart = item["start"] as! [String: String]
            let itemEnd = item["end"] as! [String: String]

            if let startDateTime = itemStart["dateTime"], let endDateTime = itemEnd["dateTime"] {
                let formatter = ISO8601DateFormatter()
                startDate = formatter.date(from: startDateTime)!
                endDate = formatter.date(from: endDateTime)!
                isAllDay = false
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                startDate = formatter.date(from: itemStart["date"]!)!
                endDate = formatter.date(from: itemEnd["date"]!)!
                isAllDay = true
            }

            let recurrent = (item["recurringEventId"] != nil) ? true : false

            return MBEvent(
                id: eventID,
                lastModifiedDate: lastModifiedDate,
                title: title,
                status: status,
                notes: notes,
                location: location,
                url: url,
                organizer: organizer,
                attendees: attendees,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                recurrent: recurrent,
                calendar: calendar
            )
        }
    }
}
