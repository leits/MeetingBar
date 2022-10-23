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

enum EventStoreProvider: String, Codable {
    case macOSEventKit = "MacOS Calendar App"
    case googleCalendar = "Google Calendar API"
}

protocol EventStore {
    func signIn() -> Promise<Void>

    func signOut() -> Promise<Void>

    func refreshSources()

    func fetchAllCalendars() -> Promise<[MBCalendar]>

    func fetchEventsForDateRange(calendars: [MBCalendar], dateFrom: Date, dateTo: Date) -> Promise<[MBEvent]>
}
