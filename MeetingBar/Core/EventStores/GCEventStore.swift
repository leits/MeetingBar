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

let googleClientNumber: String? = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_NUMBER") as? String
let googleClientSecret: String? = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as? String
let googleAuthKeychainName: String? = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_AUTH_KEYCHAIN_NAME") as? String

let isMockMode: Bool = {
    #if DEBUG
    return ProcessInfo.processInfo.environment["MOCK_GOOGLE_CALENDAR"] == "1"
    #else
    return false
    #endif
}()

enum MockError: Error, LocalizedError {
    case credentialsMissing
    case noMoreMockAccounts

    var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            return "Google OAuth credentials not configured. Set GOOGLE_CLIENT_NUMBER and GOOGLE_CLIENT_SECRET in your Xcode scheme, or enable MOCK_GOOGLE_CALENDAR=1 for mock mode."
        case .noMoreMockAccounts:
            return "All mock accounts are already added."
        }
    }
}

extension OIDServiceConfiguration: @unchecked @retroactive Sendable {}

enum AuthError: Error {
    case notSignedIn
    case refreshFailed
    case invalidResponse
}

extension OIDAuthState {
    var isTokenFresh: Bool {
        guard let exp = lastTokenResponse?.accessTokenExpirationDate else { return false }
        return exp > Date().addingTimeInterval(300)
    }

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
    private static let kClientID     = googleClientNumber.map { "\($0).apps.googleusercontent.com" } ?? ""
    private static let kClientSecret = googleClientSecret ?? ""
    private static let kRedirectURI  = googleClientNumber.map { "com.googleusercontent.apps.\($0):/oauthredirect" } ?? ""
    private static let legacyKeychainName = googleAuthKeychainName ?? "MeetingBarGoogleAuth"

    // MARK: Stored properties
    @MainActor var currentAuthorizationFlow: OIDExternalUserAgentSession?
    @MainActor var pendingAuthAccountId: String?

    private var accounts: [GoogleAccount] {
        get { Defaults[.googleAccounts] }
        set { Defaults[.googleAccounts] = newValue }
    }

    private var authStates: [String: OIDAuthState] = [:]
    private var mockAuthorizedAccounts: Set<String> = []
    private var refreshTask: [String: Task<String, Error>] = [:]
    private var mockCalendarData: [String: [[String: Any]]] = [:]
    private var mockEventData: [String: [[String: Any]]] = [:]

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
        migrateLegacyAuthStateIfNeeded()
        restoreAllAuthStates()
        pruneAccountsMissingAuthState()
    }

    // MARK: Public API

    func getAccounts() -> [GoogleAccount] {
        return accounts
    }

    func addAccount() async throws -> GoogleAccount {
        if isMockMode {
            return try await addMockAccount()
        }

        guard let redirectURL = URL(string: Self.kRedirectURI), !Self.kClientID.isEmpty else {
            throw MockError.credentialsMissing
        }

        let config = try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.discoverConfiguration(forIssuer: URL(string: Self.kIssuer)!) { cfg, err in
                if let cfg { cont.resume(returning: cfg) } else { cont.resume(throwing: err ?? NSError(domain: "GoogleSignIn", code: -1)) }
            }
        }

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
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["access_type": "offline"]
        )

        return try await withCheckedThrowingContinuation { cont in
            pendingAuthAccountId = UUID().uuidString
            currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request,
                                                               externalUserAgent: self) { [weak self] state, error in
                guard let self else { return }
                self.pendingAuthAccountId = nil
                self.currentAuthorizationFlow = nil

                if let state, let email = state.userEmail {
                    if let existing = self.accounts.first(where: { $0.email == email }) {
                        self.authStates[existing.id] = state
                        state.stateChangeDelegate = self
                        state.errorDelegate = self
                        self.persistAuthState(for: existing)
                        sendNotification("notifications_google_account_connected_title".loco(), "notifications_google_account_refreshed_body".loco(email))
                        cont.resume(returning: existing)
                        return
                    }

                    let accountId = UUID().uuidString
                    let account = GoogleAccount(id: accountId, email: email)
                    self.authStates[accountId] = state
                    state.stateChangeDelegate = self
                    state.errorDelegate = self
                    self.persistAuthState(for: account)
                    self.accounts.append(account)
                    sendNotification("notifications_google_account_connected_title".loco(), "notifications_google_account_connected_body".loco(email))
                    cont.resume(returning: account)
                } else {
                    cont.resume(throwing: error ?? NSError(domain: "GoogleSignIn", code: 1))
                }
            }
        }
    }

    private func addMockAccount() async throws -> GoogleAccount {
        let mockEmails = ["personal@example.com", "work@example.com", "dev@example.com"]
        let existingEmails = Set(accounts.map(\.email))
        let availableEmails = mockEmails.filter { !existingEmails.contains($0) }

        guard let email = availableEmails.first else {
            throw MockError.noMoreMockAccounts
        }

        let accountId = UUID().uuidString
        let account = GoogleAccount(id: accountId, email: email)

        let mockCalendars: [[String: Any]] = [
            ["id": "\(accountId):primary", "summary": "Primary", "backgroundColor": "#039BE5"],
            ["id": "\(accountId):meetings", "summary": "Meetings", "backgroundColor": "#33B679"],
            ["id": "\(accountId):personal", "summary": "Personal", "backgroundColor": "#F4511E"],
            ["id": "\(accountId):tasks", "summary": "Tasks", "backgroundColor": "#9E69AF"]
        ]

        mockCalendarData[accountId] = mockCalendars

        let now = ISO8601DateFormatter().string(from: Date())
        let mockEvents: [[String: Any]] = [
            [
                "id": "\(accountId)-evt-1",
                "summary": "Team Standup",
                "status": "confirmed",
                "updated": now,
                "start": ["dateTime": "2024-01-15T09:00:00Z"],
                "end": ["dateTime": "2024-01-15T09:30:00Z"],
                "conferenceData": [
                    "entryPoints": [
                        ["entryPointType": "video", "uri": "https://meet.google.com/abc-def"]
                    ]
                ],
                "attendees": [
                    ["email": email, "displayName": "You", "responseStatus": "accepted", "optional": false, "self": true]
                ]
            ],
            [
                "id": "\(accountId)-evt-2",
                "summary": "Lunch Break",
                "status": "confirmed",
                "updated": now,
                "start": ["dateTime": "2024-01-15T12:00:00Z"],
                "end": ["dateTime": "2024-01-15T13:00:00Z"]
            ],
            [
                "id": "\(accountId)-evt-3",
                "summary": "Sprint Planning",
                "status": "tentative",
                "updated": now,
                "start": ["dateTime": "2024-01-16T10:00:00Z"],
                "end": ["dateTime": "2024-01-16T11:00:00Z"],
                "location": "Conference Room A",
                "description": "Plan next sprint items"
            ]
        ]

        mockEventData[accountId] = mockEvents

        mockAuthorizedAccounts.insert(accountId)
        accounts.append(account)

        sendNotification("Mock: Google Account connected", "\(email) (mock)")

        return account
    }

    func removeAccount(_ account: GoogleAccount) async {
        let state = authStates.removeValue(forKey: account.id)
        accounts.removeAll { $0.id == account.id }
        Keychain.delete(for: accountKeychainKey(accountId: account.id))

        let prefix = "\(account.id):"
        Defaults[.selectedCalendarIDs] = Defaults[.selectedCalendarIDs].filter { !$0.hasPrefix(prefix) }

        mockCalendarData.removeValue(forKey: account.id)
        mockEventData.removeValue(forKey: account.id)

        if let state {
            let access  = state.lastTokenResponse?.accessToken
            let refresh = state.lastTokenResponse?.refreshToken
            await withTaskGroup(of: Void.self) { grp in
                if let acc = access {
                    grp.addTask {
                        do { try await self.revoke(token: acc) } catch { NSLog("GCEventStore: failed to revoke access token: \(error)") }
                    }
                }
                if let ref = refresh {
                    grp.addTask {
                        do { try await self.revoke(token: ref) } catch { NSLog("GCEventStore: failed to revoke refresh token: \(error)") }
                    }
                }
            }
        }
    }

    func signIn(forcePrompt _: Bool) async throws {
        if !accounts.isEmpty { return }
        _ = try await addAccount()
    }

    func signOut() async {
        for account in accounts {
            await removeAccount(account)
        }
    }

    func refreshSources() async {}

    func fetchAllCalendars() async throws -> [MBCalendar] {
        var allCalendars: [MBCalendar] = []

        for account in accounts {
            if isMockMode {
                let calendars = (mockCalendarData[account.id] ?? []).compactMap { item -> MBCalendar? in
                    guard let title = item["summary"] as? String,
                          let calendarID = item["id"] as? String,
                          let backgroundColor = item["backgroundColor"] as? String else { return nil }
                    return MBCalendar(title: title,
                                      id: calendarID,
                                      source: account.email,
                                      email: account.email,
                                      color: hexStringToUIColor(hex: backgroundColor))
                }
                allCalendars.append(contentsOf: calendars)
                continue
            }

            guard let state = authStates[account.id], state.isAuthorized else { continue }

            let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true")!
            let items = try await fetchJSON(url, forAccount: account.id)

            let calendars = items.compactMap { item -> MBCalendar? in
                guard let title = item["summary"] as? String,
                      let calendarID = item["id"] as? String,
                      let backgroundColor = item["backgroundColor"] as? String else { return nil }

                let prefixedCalendarId = "\(account.id):\(calendarID)"
                return MBCalendar(title: title,
                                  id: prefixedCalendarId,
                                  source: account.email,
                                  email: account.email,
                                  color: hexStringToUIColor(hex: backgroundColor))
            }
            allCalendars.append(contentsOf: calendars)
        }

        return allCalendars
    }

    private func getCalendarEventsForDateRange(calendar: MBCalendar,
                                               accountId: String,
                                               dateFrom: Date,
                                               dateTo: Date) async throws -> [MBEvent] {
        if isMockMode {
            let events = (mockEventData[accountId] ?? []).compactMap { item -> MBEvent? in
                GCParser.event(from: item, calendar: calendar)
            }
            return events
        }

        let iso = ISO8601DateFormatter()
        let timeMin = iso.string(from: dateFrom)
        let timeMax = iso.string(from: dateTo)

        let prefix = "\(accountId):"
        guard calendar.id.hasPrefix(prefix) else { return [] }
        let originalCalendarId = String(calendar.id.dropFirst(prefix.count))

        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(originalCalendarId)/events")!
        comps.queryItems = [
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "eventTypes", value: "default"),
            .init(name: "timeMax", value: timeMax),
            .init(name: "timeMin", value: timeMin)
        ]

        let items = try await fetchJSON(comps.url!, forAccount: accountId)
        return items.compactMap { GCParser.event(from: $0, calendar: calendar) }
    }

    func fetchEventsForDateRange(for calendars: [MBCalendar],
                                 from: Date,
                                 to: Date) async throws -> [MBEvent] {
        var result: [MBEvent] = []

        let calendarsByAccount = Dictionary(grouping: calendars) { calendar in
            if let idx = calendar.id.firstIndex(of: ":") {
                return String(calendar.id[..<idx])
            }
            return ""
        }

        for (accountId, accountCalendars) in calendarsByAccount {
            if isMockMode {
                for cal in accountCalendars {
                    let ev = try await getCalendarEventsForDateRange(calendar: cal, accountId: accountId, dateFrom: from, dateTo: to)
                    result.append(contentsOf: ev)
                }
                continue
            }

            guard let state = authStates[accountId], state.isAuthorized else { continue }

            for cal in accountCalendars {
                let ev = try await getCalendarEventsForDateRange(calendar: cal, accountId: accountId, dateFrom: from, dateTo: to)
                result.append(contentsOf: ev)
            }
        }

        return result
    }

    // MARK: - Private helpers

    private func accountKeychainKey(accountId: String) -> String {
        return "\(googleAuthKeychainName ?? "MeetingBarGoogleAuth")_\(accountId)"
    }

    private func validAccessToken(for accountId: String, forceRefresh: Bool = false) async throws -> String {
        guard let state = authStates[accountId] else { throw AuthError.notSignedIn }

        if !forceRefresh,
           state.isTokenFresh,
           let token = state.lastTokenResponse?.accessToken {
            return token
        }

        if let running = refreshTask[accountId] { return try await running.value }

        let task = Task<String, Error> {
            defer { refreshTask[accountId] = nil }
            return try await withCheckedThrowingContinuation { cont in
                if forceRefresh { state.setNeedsTokenRefresh() }

                state.performAction { [weak self] accessToken, _, error in
                    guard let self else { return }
                    if let token = accessToken {
                        cont.resume(returning: token)
                    } else {
                        if let err = error as NSError?,
                           err.domain == OIDOAuthTokenErrorDomain {
                            if let account = self.accounts.first(where: { $0.id == accountId }) {
                                Task { await self.removeAccount(account) }
                            }
                        }
                        cont.resume(throwing: error ?? AuthError.refreshFailed)
                    }
                }
            }
        }

        refreshTask[accountId] = task
        return try await task.value
    }

    // MARK: Legacy migration

    private func migrateLegacyAuthStateIfNeeded() {
        guard accounts.isEmpty,
              let data = Keychain.load(for: Self.legacyKeychainName),
              let state = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data),
              let email = state.userEmail
        else { return }

        let accountId = UUID().uuidString
        let account = GoogleAccount(id: accountId, email: email)
        let newKey = accountKeychainKey(accountId: accountId)

        do {
            let newData = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
            Keychain.save(data: newData, for: newKey)
            Keychain.delete(for: Self.legacyKeychainName)
            accounts = [account]
        } catch {
            NSLog("Failed to migrate legacy auth state: \(error)")
        }
    }

    // MARK: Keychain persistence

    private func persistAuthState(for account: GoogleAccount) {
        guard let state = authStates[account.id] else {
            Keychain.delete(for: accountKeychainKey(accountId: account.id))
            return
        }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
            Keychain.save(data: data, for: accountKeychainKey(accountId: account.id))
        } catch {
            NSLog("Error archiving OIDAuthState: \(error)")
        }
    }

    private func restoreAllAuthStates() {
        for account in accounts {
            let key = accountKeychainKey(accountId: account.id)
            guard let data = Keychain.load(for: key) else { continue }
            do {
                guard let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) else { continue }
                state.stateChangeDelegate = self
                state.errorDelegate = self
                authStates[account.id] = state
            } catch {
                NSLog("Error unarchiving OIDAuthState: \(error)")
            }
        }
    }

    private func pruneAccountsMissingAuthState() {
        let validIds = Set(authStates.keys)
        let broken = accounts.filter { !validIds.contains($0.id) }
        guard !broken.isEmpty else { return }

        for account in broken {
            NSLog("GCEventStore: pruning account %@ with missing auth state", account.email)
            Keychain.delete(for: accountKeychainKey(accountId: account.id))
        }
        accounts = accounts.filter { validIds.contains($0.id) }
    }

    // MARK: Networking helper

    private func fetchJSON(_ url: URL, forAccount accountId: String, retrying: Bool = false) async throws -> [[String: Any]] {
        let token = try await validAccessToken(for: accountId)

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 401, 403:
                if !retrying {
                    _ = try await validAccessToken(for: accountId, forceRefresh: true)
                    return try await fetchJSON(url, forAccount: accountId, retrying: true)
                }
                if let account = accounts.first(where: { $0.id == accountId }) {
                    Task { await self.removeAccount(account) }
                }
                throw AuthError.notSignedIn
            case 200...299:
                break
            default:
                throw NSError(domain: "HTTP", code: http.statusCode)
            }
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else {
            throw AuthError.invalidResponse
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

    nonisolated func didChange(_ state: OIDAuthState) {
        let stateIdentity = ObjectIdentifier(state)
        Task { @MainActor in
            for (accountId, storedState) in self.authStates where ObjectIdentifier(storedState) == stateIdentity {
                if let account = self.accounts.first(where: { $0.id == accountId }) {
                    self.persistAuthState(for: account)
                }
                break
            }
        }
    }

    nonisolated func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        let nsErr = error as NSError
        if nsErr.domain == OIDOAuthTokenErrorDomain {
            let stateIdentity = ObjectIdentifier(state)
            Task { @MainActor in
                for (accountId, storedState) in self.authStates where ObjectIdentifier(storedState) == stateIdentity {
                    if let account = self.accounts.first(where: { $0.id == accountId }) {
                        await self.removeAccount(account)
                    }
                    break
                }
            }
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
            guard let eventID = item["id"] as? String else {
                NSLog("GCParser: missing event id")
                return nil
            }

            let lastModifiedDate = ISO8601DateFormatter().date(from: item["updated"] as? String ?? "")
            let title = item["summary"] as? String
            let status = parseStatus(item["status"] as? String)
            let notes = item["description"] as? String
            let location = item["location"] as? String
            let url = parseVideoURL(item["conferenceData"] as? [String: Any])
            let organizer = parseOrganizer(item["organizer"] as? [String: String])
            let attendees = parseAttendees(item["attendees"] as? [[String: Any]])

            guard let itemStart = item["start"] as? [String: String],
                  let itemEnd = item["end"] as? [String: String]
            else {
                NSLog("GCParser: missing start/end for event \(eventID)")
                return nil
            }

            guard let dates = parseDates(itemStart, itemEnd) else {
                NSLog("GCParser: invalid date format for event \(eventID)")
                return nil
            }

            let recurrent = item["recurringEventId"] != nil

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
                startDate: dates.start,
                endDate: dates.end,
                isAllDay: dates.isAllDay,
                recurrent: recurrent,
                calendar: calendar
            )
        }
    }
}

private func parseStatus(_ raw: String?) -> MBEventStatus {
    switch raw {
    case "confirmed": return .confirmed
    case "tentative": return .tentative
    case "cancelled": return .canceled
    default: return .none
    }
}

private func parseVideoURL(_ conferenceData: [String: Any]?) -> URL? {
    guard let entryPoints = conferenceData?["entryPoints"] as? [[String: String]] else { return nil }
    guard let video = entryPoints.first(where: { $0["entryPointType"] == "video" }) else { return nil }
    return URL(string: video["uri"] ?? "")
}

private func parseOrganizer(_ raw: [String: String]?) -> MBEventOrganizer {
    MBEventOrganizer(email: raw?["email"], name: raw?["name"])
}

private func parseAttendees(_ raw: [[String: Any]]?) -> [MBEventAttendee] {
    guard let raw else { return [] }
    return raw.compactMap { json -> MBEventAttendee? in
        guard let email = json["email"] as? String else { return nil }
        let name = json["displayName"] as? String
        let optional = json["optional"] as? Bool ?? false
        let isCurrentUser = json["self"] as? Bool ?? false
        let status = parseAttendeeStatus(json["responseStatus"] as? String)
        return MBEventAttendee(email: email, name: name, status: status, optional: optional, isCurrentUser: isCurrentUser)
    }
}

private func parseAttendeeStatus(_ raw: String?) -> MBEventAttendeeStatus {
    switch raw {
    case "accepted": return .accepted
    case "declined": return .declined
    case "tentative": return .tentative
    case "needsAction": return .pending
    default: return .unknown
    }
}

private struct ParsedDates {
    let start: Date
    let end: Date
    let isAllDay: Bool
}

private func parseDates(_ start: [String: String], _ end: [String: String]) -> ParsedDates? {
    if let startStr = start["dateTime"],
       let endStr = end["dateTime"],
       let parsedStart = ISO8601DateFormatter().date(from: startStr),
       let parsedEnd = ISO8601DateFormatter().date(from: endStr) {
        return ParsedDates(start: parsedStart, end: parsedEnd, isAllDay: false)
    }
    if let startStr = start["date"],
       let endStr = end["date"],
       let parsedStart = DateFormatter.yyyyMMdd.date(from: startStr),
       let parsedEnd = DateFormatter.yyyyMMdd.date(from: endStr) {
        return ParsedDates(start: parsedStart, end: parsedEnd, isAllDay: true)
    }
    return nil
}
