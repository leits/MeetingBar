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
import PromiseKit
import SwiftyJSON

let GoogleClientNumber = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_NUMBER") as! String
let GoogleClientSecret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as! String
let GoogleAuthKeychainName = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_AUTH_KEYCHAIN_NAME") as! String

class GCEventStore: NSObject, EventStore, OIDExternalUserAgent {
    private static let kIssuer = "https://accounts.google.com"
    private static let kClientID = "\(GoogleClientNumber).apps.googleusercontent.com"
    private static let kClientSecret = GoogleClientSecret
    private static let kRedirectURI = "com.googleusercontent.apps.\(GoogleClientNumber):/oauthredirect"
    private static let AuthKeychainName = GoogleAuthKeychainName

    var currentAuthorizationFlow: OIDExternalUserAgentSession?

    static let shared = GCEventStore()

    var auth: GTMAppAuthFetcherAuthorization?

    var isAuthed: Bool {
        auth != nil
    }

    override private init() {
        super.init()
        loadState()
    }

    func refreshSources() {}

    func fetchAllCalendars() -> Promise<[MBCalendar]> {
        Promise { seal in

            loadState()

            guard let auth = self.auth else {
                return seal.fulfill([])
            }

            if let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") {
                let service = GTMSessionFetcherService()

                service.authorizer = auth
                service.fetcher(with: url).beginFetch { data, error in
                    if error != nil {
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

                            var calendars: [MBCalendar] = []

                            for (_, item) in json["items"] {
                                let calendar = MBCalendar(title: item["summary"].stringValue, ID: item["id"].stringValue, source: auth.userEmail, email: auth.userEmail, color: hexStringToUIColor(hex: item["backgroundColor"].stringValue))

                                calendars.append(calendar)
                            }
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

    private func getCalendarEventsForDateRange(calendar: MBCalendar, dateFrom: Date, dateTo: Date) -> Promise<[MBEvent]> {
        Promise { seal in
            guard let auth = self.auth else {
                seal.reject(NSError(domain: "GoogleSignIn", code: 0, userInfo: nil))
                return
            }

            let formatter = ISO8601DateFormatter()

            let timeMin = formatter.string(from: dateFrom)
            let timeMax = formatter.string(from: dateTo)

            if let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendar.ID)/events?singleEvents=true&orderBy=startTime&timeMax=\(timeMax)&timeMin=\(timeMin)") {
                let service = GTMSessionFetcherService()
                service.authorizer = auth
                NSLog("Request GoogleAPI")
                service.fetcher(with: url).beginFetch { data, error in
                    if error != nil {
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
                            var events: [MBEvent] = []

                            for (_, item) in json["items"] {
                                let eventID = item["id"].stringValue
                                let title = item["summary"].string
                                var status: MBEventStatus
                                switch item["status"].string {
                                case "confirmed":
                                    status = .confirmed
                                case "tentative":
                                    status = .tentative
                                case "cancelled":
                                    status = .canceled
                                default:
                                    status = .none
                                }

                                let notes = item["description"].string
                                let location = item["location"].string
                                let url = URL(string: item["hangoutLink"].string ?? "")

                                let organizer = MBEventOrganizer(email: item["organizer"]["email"].string, name: item["organizer"]["name"].string)

                                var attendees: [MBEventAttendee] = []
                                for (_, jsonAttendee) in item["attendees"] {
                                    let email = jsonAttendee["email"].string
                                    let name = jsonAttendee["displayName"].string
                                    let optional = jsonAttendee["optional"].bool ?? false
                                    let isCurrentUser = jsonAttendee["self"].bool ?? false

                                    var attendeeStatus: MBEventAttendeeStatus
                                    switch jsonAttendee["responseStatus"].string {
                                    case "accepted":
                                        attendeeStatus = .accepted
                                    case "declined":
                                        attendeeStatus = .declined
                                    case "tentative":
                                        attendeeStatus = .tentative
                                    case "needsAction":
                                        attendeeStatus = .inProcess
                                    default:
                                        attendeeStatus = .unknown
                                    }
                                    let attendee = MBEventAttendee(email: email, name: name, status: attendeeStatus, optional: optional, isCurrentUser: isCurrentUser)
                                    attendees.append(attendee)
                                }

                                var startDate: Date
                                var endDate: Date
                                var isAllDay: Bool

                                if item["start"]["dateTime"].exists(), item["end"]["dateTime"].exists() {
                                    let formatter = ISO8601DateFormatter()
                                    startDate = formatter.date(from: item["start"]["dateTime"].stringValue)!
                                    endDate = formatter.date(from: item["end"]["dateTime"].stringValue)!
                                    isAllDay = false
                                } else {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "yyyy-MM-dd"
                                    startDate = formatter.date(from: item["start"]["date"].stringValue)!
                                    endDate = formatter.date(from: item["end"]["date"].stringValue)!
                                    isAllDay = true
                                }

                                let event = MBEvent(
                                    ID: eventID, title: title, status: status,
                                    notes: notes, location: location, url: url,
                                    organizer: organizer, attendees: attendees,
                                    startDate: startDate, endDate: endDate,
                                    isAllDay: isAllDay, calendar: calendar
                                )
                                events.append(event)
                            }
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

    func fetchEventsForDateRange(calendars: [MBCalendar], dateFrom: Date, dateTo: Date) -> Promise<[MBEvent]> {
        Promise { seal in
            var fetchTasks: [Promise<[MBEvent]>] = []

            for calendar in calendars {
                let task = GCEventStore.shared.getCalendarEventsForDateRange(calendar: calendar, dateFrom: dateFrom, dateTo: dateTo)
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
        Promise { seal in
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
                                                          scopes: ["email", "https://www.googleapis.com/auth/calendar.calendarlist.readonly", "https://www.googleapis.com/auth/calendar.events.readonly"],
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
        Promise { seal in
            self.setAuthorization(auth: nil)
            seal.fulfill(())
        }
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

    private func saveState() {
        guard let auth = auth else {
            GTMAppAuthFetcherAuthorization.removeFromKeychain(forName: Self.AuthKeychainName)
            return
        }

        if auth.canAuthorize() {
            GTMAppAuthFetcherAuthorization.save(auth, toKeychainForName: Self.AuthKeychainName)
        } else {
            GTMAppAuthFetcherAuthorization.removeFromKeychain(forName: Self.AuthKeychainName)
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
