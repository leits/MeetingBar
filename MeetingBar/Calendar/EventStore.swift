//
//  EventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.03.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults

public enum EventStoreProvider: String, Defaults.Serializable, Codable, Sendable {
    case macOSEventKit = "MacOS Calendar App"
    case googleCalendar = "Google Calendar API"
}

/// Base contract for a calendar provider. Not main-actor isolated so providers
/// can run fetch and enumeration work off the main thread.
public protocol EventStore: AnyObject, Sendable {
    func refreshSources() async
    func fetchAllCalendars() async throws -> [MBCalendar]
    func fetchEventsForDateRange(for calendars: [MBCalendar], from: Date, to: Date) async throws
        -> [MBEvent]
    @MainActor func cancelPendingOperations()
}

public extension EventStore {
    @MainActor
    func cancelPendingOperations() {}
}

/// Extended contract for providers that require explicit sign-in/sign-out flows
/// (e.g. OAuth-based providers such as Google Calendar).
public protocol AuthenticatedEventStore: EventStore {
    func signIn(forcePrompt: Bool) async throws
    func signOut() async
}
