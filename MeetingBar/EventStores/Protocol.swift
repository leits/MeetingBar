//
//  Protocol.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.03.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults
import PromiseKit
import SwiftyJSON

enum eventStoreProvider: String, Codable {
    case MacOSEventKit = "MacOS Calendar App"
    case GoogleCalendar = "Google Calendar API"
}

protocol EventStore {
    var isAuthed: Bool { get }

    func signIn() -> Promise<Void>

    func signOut() -> Promise<Void>

    func refreshSources()

    func fetchAllCalendars() -> Promise<[MBCalendar]>

    func fetchEventsForDateRange(calendars: [MBCalendar], dateFrom: Date, dateTo: Date) -> Promise<[MBEvent]>
}
