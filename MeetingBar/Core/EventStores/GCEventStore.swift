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

struct GoogleTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiry: Date               // exact exp-time from Google
    let email: String?

    var isExpired: Bool { expiry <= Date().addingTimeInterval(30) } // 30 s buffer
}

enum GoogleTokenStorage {
    private static let service = "com.meetingbar.google.tokens"

    static func save(_ tokens: GoogleTokens?) {
        guard let tokens,
              let data = try? JSONEncoder().encode(tokens) else {
            Keychain.delete(for: service)
            return
        }
        Keychain.save(data: data, for: service)
    }

    static func load() -> GoogleTokens? {
        guard let data = Keychain.load(for: service) else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }
}

enum AuthError: Error {
    case notSignedIn
    case refreshFailed
}

extension OIDAuthState {
    var isTokenFresh: Bool {
        guard let exp = lastTokenResponse?.accessTokenExpirationDate else { return false }
        return exp > Date().addingTimeInterval(30) }
}

class GCEventStore: NSObject, EventStore, @preconcurrency OIDExternalUserAgent {
    private static let kIssuer = "https://accounts.google.com"
    private static let kClientID = "\(googleClientNumber).apps.googleusercontent.com"
    private static let kClientSecret = googleClientSecret
    private static let kRedirectURI = "com.googleusercontent.apps.\(googleClientNumber):/oauthredirect"
    private static let AuthKeychainName = googleAuthKeychainName

    var currentAuthorizationFlow: OIDExternalUserAgentSession?

    static let shared = GCEventStore()

    private var authState: OIDAuthState? {
        didSet { persistAuthState() }
    }
    private(set) var userEmail: String?

    private var signInTask: Task<Void, Error>?
    private var refreshTask: Task<String, Error>?

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.waitsForConnectivity          = true
        return URLSession(configuration: cfg)
    }()

    private var urlSession: URLSession { Self.session }

    override private init() {
        super.init()
        authState = restoreAuthState()
    }

    func signIn() async throws {
        if authState?.isAuthorized == true { return }

        let config = try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.discoverConfiguration(
                forIssuer: URL(string: Self.kIssuer)!) { cfg, err in
                if let cfg { cont.resume(returning: cfg) } else { cont.resume(throwing: err ?? NSError(domain: "GoogleSignIn", code: 0)) }
            }
        }

        try await withCheckedThrowingContinuation { cont in
            let scopes = [
                "email",
                "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
                "https://www.googleapis.com/auth/calendar.events.readonly"
            ]

            let request = OIDAuthorizationRequest(
                configuration: config,
                clientId: Self.kClientID,
                clientSecret: Self.kClientSecret,
                scopes: scopes,
                redirectURL: URL(string: Self.kRedirectURI)!,
                responseType: OIDResponseTypeCode,
                additionalParameters: nil
            )

            self.currentAuthorizationFlow = OIDAuthState
                .authState(byPresenting: request, externalUserAgent: self) { state, error in
                    if let state {
                        self.authState = state
                        sendNotification("Google Account connected", "\(self.userEmail ?? "") is connected")
                        cont.resume()
                    } else {
                        cont.resume(throwing: error ?? NSError(domain: "GoogleSignIn", code: 1))
                    }
                }
        }
    }

    func signOut() async {
        guard let state = authState else { return }

        // Revoke tokens
        let access  = state.lastTokenResponse?.accessToken
        let refresh = state.lastTokenResponse?.refreshToken
        await withTaskGroup(of: Void.self) { grp in
            if let acc = access { grp.addTask { try? await self.revoke(token: acc) } }
            if let ref = refresh { grp.addTask { try? await self.revoke(token: ref) } }
        }

        // Cancel flows and sessions
        await currentAuthorizationFlow?.cancel()           // AppAuth
        urlSession.invalidateAndCancel()                   // URLSession

        // Clean-up state and session
        clearAuthState()
    }

    func refreshSources() async {}

    func fetchAllCalendars() async throws -> [MBCalendar] {
        try await ensureSignedIn()

        let url = URL(string:
            "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true")!

        let items = try await fetchJSON(url)

        return items.compactMap { item in
            let title = item["summary"] as? String ?? ""
            let calendarID = item["id"] as? String ?? ""
            let backgroundColor = item["backgroundColor"] as? String ?? ""

            return MBCalendar(title: title, id: calendarID, source: userEmail, email: userEmail, color: hexStringToUIColor(hex: backgroundColor))
        }
    }

    private func getCalendarEventsForDateRange(
        calendar: MBCalendar,
        dateFrom: Date,
        dateTo: Date
    ) async throws -> [MBEvent] {

        let iso = ISO8601DateFormatter()
        let timeMin = iso.string(from: dateFrom)
        let timeMax = iso.string(from: dateTo)

        let url = URL(string:
          "https://www.googleapis.com/calendar/v3/calendars/\(calendar.id)/events")!

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
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

    func fetchEventsForDateRange(for calendars: [MBCalendar], from: Date, to: Date) async throws -> [MBEvent] {
        try await ensureSignedIn()
        var events: [MBEvent] = []

        for cal in calendars {
            let ev = try await getCalendarEventsForDateRange(
                calendar: cal,
                dateFrom: from,
                dateTo: to
            )
            events.append(contentsOf: ev)
        }
        return events
    }

    private func ensureSignedIn() async throws {
            if authState?.isAuthorized == true { return }

            if let running = signInTask { return try await running.value }

            let task = Task { () throws in
                defer { signInTask = nil }
                try await signIn()
            }

            signInTask = task
            try await task.value
        }

    private func persistAuthState() {
        guard let state = authState,
              let tr = state.lastTokenResponse,
              let access = tr.accessToken,
              let refresh = tr.refreshToken else {
            GoogleTokenStorage.save(nil); return
        }
        if let id = tr.idToken, let part = id.split(separator: ".").dropFirst().first,
                      let data = Data(base64URL: String(part)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            userEmail = json["email"] as? String
        }

        GoogleTokenStorage.save(.init(
            accessToken: access,
            refreshToken: refresh,
            expiry: tr.accessTokenExpirationDate ?? Date(),
            email: userEmail)
        )
    }

    private func restoreAuthState() -> OIDAuthState? {
        guard let saved = GoogleTokenStorage.load() else { return nil }
        userEmail = saved.email

        let cfg = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )

        let tokenJSON: [String: any NSCopying & NSObjectProtocol] = [
                "access_token": saved.accessToken as NSString,
                "refresh_token": saved.refreshToken as NSString,
                "expires_in": NSNumber(value: Int(saved.expiry.timeIntervalSinceNow))
            ]

        let tokenReq = OIDTokenRequest(configuration: cfg,
                                       grantType: OIDGrantTypeRefreshToken,
                                       authorizationCode: nil,
                                       redirectURL: nil,
                                       clientID: Self.kClientID,
                                       clientSecret: Self.kClientSecret,
                                       scope: nil,
                                       refreshToken: saved.refreshToken,
                                       codeVerifier: nil,
                                       additionalParameters: nil)

        let tokenResp = OIDTokenResponse(request: tokenReq, parameters: tokenJSON)

        return OIDAuthState(authorizationResponse: nil,
                            tokenResponse: tokenResp,
                            registrationResponse: nil)
    }

    private func clearAuthState() {
        authState = nil
        userEmail = nil
        GoogleTokenStorage.save(nil)
    }

    private func validAccessToken() async throws -> String {
        guard let state = authState else { throw AuthError.notSignedIn }

        // Return token if fresh
        if state.isTokenFresh,
           let token = state.lastTokenResponse?.accessToken {
            return token
        }

        // Wait for refresh if running
        if let running = refreshTask {
            return try await running.value
        }

        // Create task for refresh
        let task = Task<String, Error> {
            defer { refreshTask = nil }
            return try await withCheckedThrowingContinuation { cont in
                state.setNeedsTokenRefresh()
                state.performAction { newToken, _, error in
                    if let newToken {
                        cont.resume(returning: newToken)
                    } else {
                        cont.resume(throwing: error ?? AuthError.refreshFailed)
                    }
                }
            }
        }

        refreshTask = task
        return try await task.value
    }

    @MainActor
    func present(_ request: OIDExternalUserAgentRequest, session _: OIDExternalUserAgentSession) -> Bool {
        if let url = request.externalUserAgentRequestURL(),
           NSWorkspace.shared.open(url) {
            return true
        }

        return false
    }

    @MainActor
    func dismiss(animated _: Bool, completion: @escaping () -> Void) {
        completion()
    }

    // MARK: - Networking helper
    private func fetchJSON(_ url: URL) async throws -> [[String: Any]] {
        let token = try await validAccessToken()

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 401, 403:
                clearAuthState()                  // refresh & keychain wipe
                throw AuthError.notSignedIn
            case 200...299:
                break                            // OK
            default:
                throw NSError(domain: "HTTP", code: http.statusCode)
            }
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return root["items"] as? [[String: Any]] ?? []
    }

    private func revoke(token: String) async throws {
        var req = URLRequest(
            url: URL(string: "https://oauth2.googleapis.com/revoke")!
        )
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "token=\(token)".data(using: .utf8)

        let (_, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw NSError(domain: "GoogleRevoke", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // MARK: - Google JSON ➜ MBEvent

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
