//
//  Protocol.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.03.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults

public enum EventStoreProvider: String, Defaults.Serializable, Codable {
    case macOSEventKit = "MacOS Calendar App"
    case googleCalendar = "Google Calendar API"
}

@MainActor
public protocol EventStore: AnyObject, Sendable {
    func signIn() async throws
    func signOut() async
    func refreshSources() async

    func fetchAllCalendars() async throws -> [MBCalendar]

    func fetchEventsForDateRange(for calendars: [MBCalendar], from: Date, to: Date) async throws -> [MBEvent]
}
