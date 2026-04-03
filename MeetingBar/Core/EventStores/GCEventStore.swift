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
    private static let kClientID     = "\(googleClientNumber).apps.googleusercontent.com"
    private static let kClientSecret = googleClientSecret
    private static let kRedirectURI  = "com.googleusercontent.apps.\(googleClientNumber):/oauthredirect"
    private static let legacyKeychainName = googleAuthKeychainName

    // MARK: Stored properties
    @MainActor var currentAuthorizationFlow: OIDExternalUserAgentSession?
    @MainActor var pendingAuthAccountId: String?

    private var accounts: [GoogleAccount] {
        get { Defaults[.googleAccounts] }
        set { Defaults[.googleAccounts] = newValue }
    }

    private var authStates: [String: OIDAuthState] = [:]
    private var refreshTask: [String: Task<String, Error>] = [:]

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
    }

    // MARK: Public API

    func getAccounts() -> [GoogleAccount] {
        return accounts
    }

    func addAccount() async throws -> GoogleAccount {
        let accountId = UUID().uuidString

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
            redirectURL: URL(string: Self.kRedirectURI)!,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["access_type": "offline"]
        )

        return try await withCheckedThrowingContinuation { cont in
            pendingAuthAccountId = accountId
            currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request,
                                                               externalUserAgent: self) { [weak self] state, error in
                guard let self else { return }
                self.pendingAuthAccountId = nil
                self.currentAuthorizationFlow = nil

                if let state, let email = state.userEmail {
                    let account = GoogleAccount(id: accountId, email: email)
                    self.authStates[accountId] = state
                    state.stateChangeDelegate = self
                    state.errorDelegate = self
                    self.persistAuthState(for: account)
                    self.accounts.append(account)
                    sendNotification("Google Account connected", "\(email) is connected")
                    cont.resume(returning: account)
                } else {
                    cont.resume(throwing: error ?? NSError(domain: "GoogleSignIn", code: 1))
                }
            }
        }
    }

    func removeAccount(_ account: GoogleAccount) async {
        if let state = authStates[account.id] {
            let access  = state.lastTokenResponse?.accessToken
            let refresh = state.lastTokenResponse?.refreshToken
            await withTaskGroup(of: Void.self) { grp in
                if let acc = access { grp.addTask { try? await self.revoke(token: acc) } }
                if let ref = refresh { grp.addTask { try? await self.revoke(token: ref) } }
            }
            authStates.removeValue(forKey: account.id)
        }

        accounts.removeAll { $0.id == account.id }
        Keychain.delete(for: accountKeychainKey(accountId: account.id))

        let prefix = "\(account.id):"
        Defaults[.selectedCalendarIDs] = Defaults[.selectedCalendarIDs].filter { !$0.hasPrefix(prefix) }
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
        return "\(googleAuthKeychainName)_\(accountId)"
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

            guard let itemStart = item["start"] as? [String: String],
                  let itemEnd = item["end"] as? [String: String]
            else {
                NSLog("GCParser: missing start/end for event \(eventID)")
                return nil
            }

            let startDate: Date
            let endDate: Date
            let isAllDay: Bool

            if let startDateTime = itemStart["dateTime"],
               let endDateTime = itemEnd["dateTime"],
               let parsedStart = ISO8601DateFormatter().date(from: startDateTime),
               let parsedEnd = ISO8601DateFormatter().date(from: endDateTime) {
                startDate = parsedStart
                endDate = parsedEnd
                isAllDay = false
            } else if let startDateStr = itemStart["date"],
                      let endDateStr = itemEnd["date"],
                      let parsedStart = DateFormatter.yyyyMMdd.date(from: startDateStr),
                      let parsedEnd = DateFormatter.yyyyMMdd.date(from: endDateStr) {
                startDate = parsedStart
                endDate = parsedEnd
                isAllDay = true
            } else {
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
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                recurrent: recurrent,
                calendar: calendar
            )
        }
    }
}
