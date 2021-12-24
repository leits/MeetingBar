//
//  GCal.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 21.11.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import AppAuthCore
import AppKit
import Defaults
import Foundation
import GTMAppAuth
import PromiseKit
import SwiftyJSON

class MBCalendar: Hashable {
    let title: String
    let calendarIdentifier: String
    let source: String?
    var selected: Bool = false
    let color: NSColor

    init(json: JSON, source: String?) {
        self.source = source
        title = json["summary"].stringValue
        calendarIdentifier = json["id"].stringValue
        color = hexStringToUIColor(hex: json["backgroundColor"].stringValue)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(calendarIdentifier)
    }

    static func == (lhs: MBCalendar, rhs: MBCalendar) -> Bool {
        lhs.calendarIdentifier == rhs.calendarIdentifier
    }
}

enum MBEventStatus: Int {
    case none = 0
    case confirmed = 1
    case tentative = 2
    case canceled = 3
}

class MBEventOrganizer {
    let name: String
    let email: String

    init(json: JSON) {
        email = json["email"].string ?? ""
        name = json["displayName"].string ?? email
    }
}

enum MBEventAttendeeStatus: Int {
    case unknown = 0
    case pending = 1
    case accepted = 2
    case declined = 3
    case tentative = 4
    case delegated = 5
    case completed = 6
    case inProcess = 7
}

class MBEventAttendee {
    let name: String
    let email: String?
    let status: MBEventAttendeeStatus
    var optional: Bool = false
    let isCurrentUser: Bool

    init(json: JSON) {
        email = json["email"].string
        name = json["displayName"].string ?? email ?? "status_bar_submenu_attendees_no_name".loco()

        if json["optional"].exists() {
            optional = json["optional"].boolValue
        }
        if json["self"].exists() {
            isCurrentUser = json["self"].boolValue
        } else {
            isCurrentUser = false
        }

        let raw_satus = json["responseStatus"].string
        if raw_satus == "accepted" {
            status = .accepted
        } else if raw_satus == "declined" {
            status = .declined
        } else if raw_satus == "tentative" {
            status = .tentative
        } else if raw_satus == "needsAction" {
            status = .inProcess
        } else {
            status = .unknown
        }
    }
}

class MBEvent {
    let eventIdentifier: String
    let calendar: MBCalendar
    let title: String
    var status: MBEventStatus = .none
    var organizer: MBEventOrganizer?
    let url: URL?
    let notes: String?
    let hasNotes: Bool
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    var attendees: [MBEventAttendee] = []

    init(json: JSON, calendar: MBCalendar) {
        self.calendar = calendar
        eventIdentifier = json["id"].stringValue
        title = json["summary"].string ?? "status_bar_no_title".loco()
        if let raw_satus = json["status"].string {
            if raw_satus == "confirmed" {
                status = .confirmed
            } else if raw_satus == "tentative" {
                status = .tentative
            } else if raw_satus == "cancelled" {
                status = .canceled
            }
        }
        notes = json["description"].string
        hasNotes = json["description"].exists()
        location = json["location"].string
        url = URL(string: json["hangoutLink"].string ?? "")

        if json["organizer"].exists() {
            organizer = MBEventOrganizer(json: json["organizer"])
        }

        if json["attendees"].exists() {
            for (_, raw_attendee) in json["attendees"] {
                let attendee = MBEventAttendee(json: raw_attendee)
                attendees.append(attendee)
            }
        } else {}

        if json["start"]["dateTime"].exists(), json["end"]["dateTime"].exists() {
            let formatter = ISO8601DateFormatter()
            startDate = formatter.date(from: json["start"]["dateTime"].stringValue)!
            endDate = formatter.date(from: json["end"]["dateTime"].stringValue)!
            isAllDay = false
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            startDate = formatter.date(from: json["start"]["date"].stringValue)!
            endDate = formatter.date(from: json["end"]["date"].stringValue)!
            isAllDay = true
        }
    }
}

class GCEventStore: NSObject, OIDExternalUserAgent {
    static let kYourClientNumer = GoogleClientNumber
    static let kIssuer = "https://accounts.google.com"
    static let kClientID = "\(GoogleClientNumber).apps.googleusercontent.com"
    static let kClientSecret = GoogleClientSecret
    static let kRedirectURI = "com.googleusercontent.apps.\(GoogleClientNumber):/oauthredirect"
    static let kExampleAuthorizerKey = "REPLACE_BY_YOUR_AUTHORIZATION_KEY"

    var currentAuthorizationFlow: OIDExternalUserAgentSession?

    static let shared = GCEventStore()

    var auth: GTMAppAuthFetcherAuthorization?

    var isAuthed: Bool {
        return auth != nil
    }

    override private init() {
        super.init()
        loadState()
    }

    func getAllCalendars() -> Promise<[MBCalendar]> {
        return Promise { seal in
            
            loadState()

            guard let auth = self.auth else {
                seal.reject(NSError(domain: "GoogleSignIn", code: 0, userInfo: nil))
                return
            }

            if let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") {

                let service = GTMSessionFetcherService()

                service.authorizer = auth
                service.fetcher(with: url).beginFetch { data, error in
                    if (error != nil) {
                        if (error as NSError?)?.domain == OIDOAuthTokenErrorDomain {
                            self.setAuthorization(auth: nil)
                        }
                        NSLog(error?.localizedDescription ?? "")
                        seal.reject(error!)
                        return
                    }

                    if let data = data {
                        do {
                            let json = try JSON(data: data)
                            let calendars = json["items"].map { MBCalendar(json: $1, source: auth.userEmail) }
                            return seal.fulfill(calendars)
                        } catch {
                            NSLog(error.localizedDescription)
                            seal.reject(error)
                        }
                    } else {
                        seal.reject(NSError(domain: "GoogleSignIn", code: 0, userInfo: nil))
                    }
                }
            }
        }
    }

    func getCalendarEventsForDate(calendar: MBCalendar, dateFrom: Date, dateTo: Date) -> Promise<[MBEvent]> {
        return Promise { seal in
            guard let auth = self.auth else {
                seal.reject(NSError(domain: "GoogleSignIn", code: 0, userInfo: nil))
                return
            }

            let formatter = ISO8601DateFormatter()

            let timeMin = formatter.string(from: dateFrom)
            let timeMax = formatter.string(from: dateTo)

            if let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendar.calendarIdentifier)/events?singleEvents=true&orderBy=startTime&timeMax=\(timeMax)&timeMin=\(timeMin)") {
                let service = GTMSessionFetcherService()
                service.authorizer = auth
                NSLog("Request GoogleAPI")
                service.fetcher(with: url).beginFetch { data, error in
                    if (error != nil) {
                        if (error as NSError?)?.domain == OIDOAuthTokenErrorDomain {
                            self.setAuthorization(auth: nil)
                        }
                        NSLog(error?.localizedDescription ?? "")
                        seal.reject(error!)
                        return
                    }

                    if let data = data {
                        do {
                            let json = try JSON(data: data)
                            let events = json["items"].map { MBEvent(json: $1, calendar: calendar) }
                            return seal.fulfill(events)
                        } catch {
                            seal.reject(error)
                        }
                    } else {
                        seal.reject(NSError(domain: "GoogleSignIn", code: 0, userInfo: nil))
                    }
                }
            }
        }
    }

    func loadEventsForDate(calendars: [MBCalendar], dateFrom: Date, dateTo: Date) -> Promise<[MBEvent]> {
        return Promise { seal in
            var fetchTasks: [Promise<[MBEvent]>] = []

            for calendar in calendars {
                let task = GCEventStore.shared.getCalendarEventsForDate(calendar: calendar, dateFrom: dateFrom, dateTo: dateTo)
                fetchTasks.append(task)
            }

            when(resolved: fetchTasks).done { (results: [Result]) in
                var events: [MBEvent] = []
                for result in results {
                    switch result {
                    case let .fulfilled(t):
                        events.append(contentsOf: t)
                    case .rejected:
                        continue
                    }
                }
                return seal.fulfill(events)
            }
        }
    }

    func signIn() -> Promise<Void> {
        return Promise { seal in
            if self.auth != nil, self.auth!.canAuthorize() {
                seal.fulfill(())
            } else {
                OIDAuthorizationService.discoverConfiguration(forIssuer: URL(string: Self.kIssuer)!) { config, error in
                    guard error == nil else {
                        seal.reject(error!)
                        return
                    }

                    guard let config = config else {
                        seal.reject(NSError(domain: "GoogleSignIn", code: 0, userInfo: nil))
                        return
                    }

                    let request = OIDAuthorizationRequest(configuration: config,
                                                          clientId: Self.kClientID,
                                                          clientSecret: Self.kClientSecret,
                                                          scopes: ["email", "https://www.googleapis.com/auth/calendar.readonly", "https://www.googleapis.com/auth/calendar.events.readonly"],
                                                          redirectURL: URL(string: Self.kRedirectURI)!,
                                                          responseType: OIDResponseTypeCode,
                                                          additionalParameters: nil)

                    self.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, externalUserAgent: self, callback: { state, error in
                        guard error == nil else {
                            seal.reject(error!)
                            return
                        }

                        if state != nil {
                            self.setAuthorization(auth: GTMAppAuthFetcherAuthorization(authState: state!))
                            seal.fulfill(())
                        } else {
                            seal.reject(NSError(domain: "GoogleSignIn", code: 0, userInfo: nil))
                        }
                    })
                }
            }
        }
    }

    func signOut() -> Promise<Void> {
        return Promise { seal in
            self.setAuthorization(auth: nil)
            seal.fulfill(())
        }
    }

    private func setAuthorization(auth: GTMAppAuthFetcherAuthorization?) {
        self.auth = auth
        saveState()
    }

    private func loadState() {
        if let auth = GTMAppAuthFetcherAuthorization(fromKeychainForName: Self.kExampleAuthorizerKey) {
            setAuthorization(auth: auth)
        }
    }

    private func saveState() {
        guard let auth = auth else {
            GTMAppAuthFetcherAuthorization.removeFromKeychain(forName: Self.kExampleAuthorizerKey)
            return
        }

        if auth.canAuthorize() {
            GTMAppAuthFetcherAuthorization.save(auth, toKeychainForName: Self.kExampleAuthorizerKey)
        } else {
            GTMAppAuthFetcherAuthorization.removeFromKeychain(forName: Self.kExampleAuthorizerKey)
        }
    }

    func present(_ request: OIDExternalUserAgentRequest, session _: OIDExternalUserAgentSession) -> Bool {
        if let url = request.externalUserAgentRequestURL(),
           NSWorkspace.shared.open(url)
        {
            return true
        }

        return false
    }

    func dismiss(animated _: Bool, completion: @escaping () -> Void) {
        completion()
    }
}

func filterEvents(_ events: [MBEvent]) -> [MBEvent] {
    let showAlldayEvents: Bool = Defaults[.allDayEvents] == AlldayEventsAppereance.show

    let calendarEvents = events.filter { ($0.isAllDay && showAlldayEvents) || Calendar.current.isDate($0.startDate, inSameDayAs: Date()) }

    var filteredCalendarEvents: [MBEvent] = []

    for calendarEvent in calendarEvents {
        for pattern in Defaults[.filterEventRegexes] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                if !hasMatch(text: calendarEvent.title, regex: regex) {
                    continue
                }
            }
        }

        var addEvent = false
        if calendarEvent.isAllDay {
            if Defaults[.allDayEvents] == AlldayEventsAppereance.show {
                addEvent = true
            } else if Defaults[.allDayEvents] == AlldayEventsAppereance.show_with_meeting_link_only {
                let result = getMeetingLink(calendarEvent)

                if result?.url != nil {
                    addEvent = true
                }
            }
        } else {
            if Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.hide_without_meeting_link {
                let result = getMeetingLink(calendarEvent)

                if result?.url != nil {
                    addEvent = true
                }
            } else {
                addEvent = true
            }
        }

        let status = getEventParticipantStatus(calendarEvent)
        if status == .pending, Defaults[.showPendingEvents] == .hide {
            addEvent = false
        }

        if addEvent {
            filteredCalendarEvents.append(calendarEvent)
        }
    }
    return filteredCalendarEvents
}
