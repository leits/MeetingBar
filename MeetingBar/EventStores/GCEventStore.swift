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
import GTMAppAuth

let googleClientNumber = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_NUMBER") as! String
let googleClientSecret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as! String
let googleAuthKeychainName = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_AUTH_KEYCHAIN_NAME") as! String

extension OIDServiceConfiguration: @unchecked @retroactive Sendable {}
extension GTMSessionFetcherService: @unchecked @retroactive Sendable {}

class GCEventStore: NSObject, EventStore, @preconcurrency OIDExternalUserAgent {
    private static let kIssuer = "https://accounts.google.com"
    private static let kClientID = "\(googleClientNumber).apps.googleusercontent.com"
    private static let kClientSecret = googleClientSecret
    private static let kRedirectURI = "com.googleusercontent.apps.\(googleClientNumber):/oauthredirect"
    private static let AuthKeychainName = googleAuthKeychainName

    var currentAuthorizationFlow: OIDExternalUserAgentSession?

    static let shared = GCEventStore()

    var auth: GTMAppAuthFetcherAuthorization?
    lazy var fetcherService = GTMSessionFetcherService()

    override private init() {
        super.init()
        loadState()
    }

    func signIn() async throws {
        if let auth, auth.canAuthorize() { return }

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
                    additionalParameters: nil)

                self.currentAuthorizationFlow = OIDAuthState
                    .authState(byPresenting: request, externalUserAgent: self) { state, error in
                        if let state {
                            self.setAuthorization(auth:
                                GTMAppAuthFetcherAuthorization(authState: state))
                            sendNotification("Google Account connected", "\(self.auth?.userEmail ?? "") is connected")
                            cont.resume()
                        } else {
                            cont.resume(throwing: error ?? NSError(domain: "GoogleSignIn", code: 1))
                        }
                    }
            }
    }

    func signOut() async {
        setAuthorization(auth: nil)
        fetcherService.stopAllFetchers()
    }

    func refreshSources() async {}

    func fetchAllCalendars() async throws -> [MBCalendar] {
        loadState()
        guard let auth else { return [] }

        let url = URL(string:
            "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true")!

        let items = try await fetchJSON(url, authorizedWith: auth)

        return items.compactMap { item in
            let title = item["summary"] as? String ?? ""
            let calendarID = item["id"] as? String ?? ""
            let backgroundColor = item["backgroundColor"] as? String ?? ""

            return MBCalendar(title: title, ID: calendarID, source: auth.userEmail, email: auth.userEmail, color: hexStringToUIColor(hex: backgroundColor))
        }
    }

    private func getCalendarEventsForDateRange(
        calendar: MBCalendar,
        dateFrom: Date,
        dateTo: Date) async throws -> [MBEvent] {

        guard let auth else { throw NSError(domain: "GoogleSignIn", code: 0) }

        let iso = ISO8601DateFormatter()
        let timeMin = iso.string(from: dateFrom)
        let timeMax = iso.string(from: dateTo)

        let url = URL(string:
          "https://www.googleapis.com/calendar/v3/calendars/\(calendar.ID)/events" +
          "?singleEvents=true&orderBy=startTime&timeMax=\(timeMax)&timeMin=\(timeMin)")!

        let items = try await fetchJSON(url, authorizedWith: auth)

        return items.compactMap { GCParser.event(from: $0, calendar: calendar) }
    }

    func fetchEventsForDateRange(for calendars: [MBCalendar], from: Date, to: Date) async throws -> [MBEvent] {

        var events: [MBEvent] = []

        for cal in calendars {
            let ev = try await getCalendarEventsForDateRange(
                       calendar: cal,
                       dateFrom: from,
                       dateTo: to)
            events.append(contentsOf: ev)
        }
        return events
    }

    private func setAuthorization(auth: GTMAppAuthFetcherAuthorization?) {
        self.auth = auth
        saveState()
    }

    private func loadState() {
        if let auth = GTMAppAuthFetcherAuthorization(fromKeychainForName: Self.AuthKeychainName) {
            setAuthorization(auth: auth)
        }
    }

    @MainActor
    private func saveState() {
        let key = Self.AuthKeychainName

        guard let auth = self.auth else {
            GTMAppAuthFetcherAuthorization.removeFromKeychain(forName: key)
            return
        }

        if auth.canAuthorize() {
            GTMAppAuthFetcherAuthorization.save(auth, toKeychainForName: key)
        } else {
            GTMAppAuthFetcherAuthorization.removeFromKeychain(forName: key)
        }
    }

    func present(_ request: OIDExternalUserAgentRequest, session _: OIDExternalUserAgentSession) -> Bool {
        if let url = request.externalUserAgentRequestURL(),
           NSWorkspace.shared.open(url) {
            return true
        }

        return false
    }

    nonisolated func dismiss(animated _: Bool, completion: @escaping () -> Void) {
        completion()
    }

    // MARK: - Networking helper
    private func fetchJSON(_ url: URL,
                           authorizedWith auth: GTMAppAuthFetcherAuthorization)
    async throws -> [[String: Any]] {

        try await withCheckedThrowingContinuation { cont in
            fetcherService.authorizer = auth
            fetcherService.fetcher(with: url).beginFetch { data, error in
                if let error { cont.resume(throwing: error); return }
                guard let data else {
                    cont.resume(throwing: NSError(domain: "GC", code: 2)); return
                }
                do {
                    let top = try JSONSerialization.jsonObject(with: data)
                                                 as? [String: Any] ?? [:]
                    let items = top["items"] as? [[String: Any]] ?? []
                    Task { @MainActor in cont.resume(returning: items) }
                } catch {
                    cont.resume(throwing: error)
                }
            }
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
