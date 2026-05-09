//
//  AppModelTestHarness.swift
//  MeetingBarTests
//

import Combine
import Foundation

@testable import MeetingBar

@MainActor
final class AppModelTestHarness {
    let eventsSubject = PassthroughSubject<[MBEvent], Never>()
    let calendarsSubject = PassthroughSubject<([MBCalendar], EventStoreProvider), Never>()

    private(set) var refreshCallCount = 0
    private(set) var reconciledEventIDs: [[String]] = []
    private(set) var providerChanges: [(provider: EventStoreProvider, signOut: Bool)] = []
    private(set) var calendarSelections: [(id: String, selected: Bool)] = []

    let fixedNow: Date

    private lazy var environment = AppEnvironment(
        eventsPublisher: eventsSubject.eraseToAnyPublisher(),
        calendarsPublisher: calendarsSubject.eraseToAnyPublisher(),
        triggerRefresh: { [weak self] in
            self?.refreshCallCount += 1
        },
        reconcileNotifications: { [weak self] events in
            self?.reconciledEventIDs.append(events.map(\.id))
        },
        changeProvider: { [weak self] provider, signOut in
            self?.providerChanges.append((provider, signOut))
        },
        toggleCalendarSelection: { [weak self] id, selected in
            self?.calendarSelections.append((id, selected))
        },
        now: { [fixedNow] in fixedNow }
    )

    lazy var model = AppModel(environment: environment)

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        fixedNow = now
    }

    func publishCalendars(_ calendars: [MBCalendar],
                          provider: EventStoreProvider = .macOSEventKit) {
        calendarsSubject.send((calendars, provider))
    }

    func publishEvents(_ events: [MBEvent]) {
        eventsSubject.send(events)
    }

    func flushAsyncActions() async {
        await Task.yield()
        await Task.yield()
    }
}
