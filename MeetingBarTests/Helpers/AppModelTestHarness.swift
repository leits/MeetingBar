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
    private(set) var openedMeetingIDs: [String] = []
    private(set) var dismissedEventIDs: [String] = []
    private(set) var undismissedEventIDs: [String] = []
    private(set) var clearDismissedEventsCallCount = 0
    private(set) var toggleMeetingTitleVisibilityCallCount = 0
    private(set) var snoozedEvents: [(id: String, action: NotificationEventTimeAction)] = []
    private(set) var completedOnboardingProviders: [EventStoreProvider] = []
    private(set) var openPreferencesCallCount = 0
    private(set) var resumedOAuthURLs: [URL] = []

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
        openMeeting: { [weak self] event in
            self?.openedMeetingIDs.append(event.id)
        },
        dismissEvent: { [weak self] event in
            self?.dismissedEventIDs.append(event.id)
        },
        undismissEvent: { [weak self] eventID in
            self?.undismissedEventIDs.append(eventID)
        },
        clearDismissedEvents: { [weak self] in
            self?.clearDismissedEventsCallCount += 1
        },
        toggleMeetingTitleVisibility: { [weak self] in
            self?.toggleMeetingTitleVisibilityCallCount += 1
        },
        snoozeEvent: { [weak self] event, action in
            self?.snoozedEvents.append((event.id, action))
        },
        completeOnboarding: { [weak self] provider in
            self?.completedOnboardingProviders.append(provider)
        },
        openPreferences: { [weak self] in
            self?.openPreferencesCallCount += 1
        },
        resumeOAuthFlow: { [weak self] url in
            self?.resumedOAuthURLs.append(url)
        },
        clock: .fixed(fixedNow)
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
