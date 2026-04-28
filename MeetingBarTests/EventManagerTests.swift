//
//  EventManagerTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import Combine
@testable import MeetingBar
import XCTest
import Defaults
import AppAuthCore

@MainActor
class EventManagerTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    func testInjectedStorePublishesCalendarsAndEvents() {
        // 1) Prepare fakes
        let fakeCal = MBCalendar(title: "Cal A", id: "calA", source: nil, email: nil, color: .black)
        let fakeEvt = makeFakeEvent(
            id: "E1",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(3600)
        )
        let fakeStore = FakeEventStore(
            calendars: [fakeCal],
            events: [fakeEvt]
        )

        // 2) Create manager with test initializer
        let manager = EventManager(
            provider: fakeStore,
            refreshInterval: 0.05
        )

        // 3) Observe first non-empty values of calendars & events
        let calExpectation = expectation(description: "calendars published")
        manager.$calendars
            .drop(while: \.isEmpty)
            .first()
            .sink { cals in
                XCTAssertEqual(cals, [fakeCal])
                calExpectation.fulfill()
            }
            .store(in: &cancellables)

        let evtExpectation = expectation(description: "events published")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { evts in
                XCTAssertEqual(evts, [fakeEvt])
                evtExpectation.fulfill()
            }
            .store(in: &cancellables)

        // 4) Wait
        wait(for: [calExpectation, evtExpectation], timeout: 1.0)
    }
}

@MainActor class EventManagerSwitchProviderTests: BaseTestCase {

    private var cancellables = Set<AnyCancellable>()

    func testSwitchProviderPublishesNewEvents() async throws {
        // Arrange: two fake stores with different events
        let firstEvent  = makeFakeEvent(
            id: "A",
            start: Date(),
            end: Date().addingTimeInterval(3600)
        )
        let secondEvent = makeFakeEvent(
            id: "B",
            start: Date().addingTimeInterval(7200),
            end: Date().addingTimeInterval(10_800)
        )

        let storeA = FakeEventStore(events: [firstEvent])
        let storeB = FakeEventStore(events: [secondEvent])

        // Start EventManager with Store A
        let manager = EventManager(provider: storeA, refreshInterval: 0)

        // Expect the first publication to contain [firstEvent]
        let initialExp = expectation(description: "initial events")
        manager.$events
            .drop(while: \.isEmpty)
            .first()                                     // Failure == Never
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { events in
                    XCTAssertEqual(events, [firstEvent])
                    initialExp.fulfill()
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [initialExp], timeout: 1.0)

        // Prepare second expectation BEFORE switching the store
        let switchedExp = expectation(description: "events after switch")
        manager.$events
            .dropFirst()                                // skip current value
            .first()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { events in
                    XCTAssertEqual(events, [secondEvent])
                    switchedExp.fulfill()
                }
            )
            .store(in: &cancellables)

        // Act: replace the provider and trigger refresh
        manager.provider = storeB
        try await manager.refreshSources()              // sends refreshSubject

        await fulfillment(of: [switchedExp], timeout: 1.0)

    }
}

@MainActor
final class RefreshTriggerTests: BaseTestCase {

    private var cancellables = Set<AnyCancellable>()

    func test_eventsRefreshWhenShowEventsPeriodChanges() {
        // Fake store that can swap its stubbed events on the fly
        let first  = makeFakeEvent(id: "P-A",
                                   start: .init(),
                                   end: .init().addingTimeInterval(60))
        let second = makeFakeEvent(id: "P-B",
                                   start: .init().addingTimeInterval(120),
                                   end: .init().addingTimeInterval(240))

        let store = FakeEventStore(events: [first])

        // Start with `.today`
        Defaults[.showEventsForPeriod] = .today
        let manager = EventManager(provider: store, refreshInterval: 0)

        // Expect initial publication with [first]
        let initialExp = expectation(description: "initial events")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { events in
                XCTAssertEqual(events, [first])
                initialExp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [initialExp], timeout: 1.0)

        // Prepare expectation BEFORE flipping the Default
        let switchedExp = expectation(description: "events after period change")
        manager.$events
            .dropFirst()            // skip current value
            .first()
            .sink { events in
                XCTAssertEqual(events, [second])
                switchedExp.fulfill()
            }
            .store(in: &cancellables)

        // ↻ Mutate store, then toggle Default → Combine trigger fires
        store.stubbedEvents = [second]
        Defaults[.showEventsForPeriod] = .today_n_tomorrow

        wait(for: [switchedExp], timeout: 1.0)
    }

    func test_refreshSourcesPublishesEvents() async throws {
        let ev = makeFakeEvent(id: "R",
                               start: .init(),
                               end: .init().addingTimeInterval(60))
        let store = FakeEventStore(events: [ev])
        let manager = EventManager(provider: store, refreshInterval: 0)

        // Expectation BEFORE calling refreshSources()
        let exp = expectation(description: "events after manual refresh")
        manager.$events
            .dropFirst()          // skip the initial []
            .first()              // grab only the first non-empty publish
            .sink { events in
                XCTAssertEqual(events, [ev])
                exp.fulfill()
            }
            .store(in: &cancellables)

        // Act
        try await manager.refreshSources()

        await fulfillment(of: [exp], timeout: 1)
    }
}

@MainActor
final class GCEventStoreCoverageTests: BaseTestCase {
    func testSignInSkipLogicHonorsForcePrompt() {
        let authorizedWithRefresh = makeAuthState(refreshToken: "refresh-token-1")
        XCTAssertTrue(GCEventStore.shouldSkipSignIn(forcePrompt: false, state: authorizedWithRefresh))
        XCTAssertFalse(GCEventStore.shouldSkipSignIn(forcePrompt: true, state: authorizedWithRefresh))

        let authorizedWithoutRefresh = makeAuthState(refreshToken: nil)
        XCTAssertFalse(GCEventStore.shouldSkipSignIn(forcePrompt: false, state: authorizedWithoutRefresh))
    }

    func testEnsureSignedInUsesRefreshTokenSessionChecks() async throws {
        let store = GCEventStore.shared
        let originalState = store._test_getAuthState()
        defer {
            store._test_setAuthState(originalState)
            store._test_setSignInTask(nil)
        }

        let precompletedTask = Task<Void, Error> {}
        store._test_setSignInTask(precompletedTask)

        store._test_setAuthState(makeAuthState(refreshToken: nil))
        try await store._test_ensureSignedIn()

        store._test_setAuthState(makeAuthState(refreshToken: "refresh-token-1"))
        store._test_setSignInTask(nil)
        try await store._test_ensureSignedIn()
    }

    func testSignOutReadsRefreshTokenFromAuthState() async throws {
        let store = GCEventStore.shared
        let originalState = store._test_getAuthState()
        defer {
            store._test_setAuthState(originalState)
            store._test_setSignInTask(nil)
        }

        store._test_setAuthState(makeAuthorizationOnlyState())
        await store.signOut()
    }

    private func makeAuthState(refreshToken: String?) -> OIDAuthState {
        let request = authorizationRequest()
        let response = OIDAuthorizationResponse(
            request: request,
            parameters: [
                "code": "authorization-code" as NSString
            ]
        )
        guard let tokenRequest = response.tokenExchangeRequest() else {
            fatalError("Failed to build token request for GCEventStore coverage test")
        }

        var tokenParameters: [String: NSObject & NSCopying] = [
            "access_token": "access-token-1" as NSString,
            "token_type": "Bearer" as NSString,
            "expires_in": 3600 as NSNumber
        ]
        if let refreshToken {
            tokenParameters["refresh_token"] = refreshToken as NSString
        }
        let tokenResponse = OIDTokenResponse(request: tokenRequest, parameters: tokenParameters)
        return OIDAuthState(authorizationResponse: response, tokenResponse: tokenResponse)
    }

    private func makeAuthorizationOnlyState() -> OIDAuthState {
        let request = authorizationRequest()
        let response = OIDAuthorizationResponse(
            request: request,
            parameters: [
                "code": "authorization-code" as NSString
            ]
        )
        return OIDAuthState(authorizationResponse: response)
    }

    private func authorizationRequest() -> OIDAuthorizationRequest {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
        return OIDAuthorizationRequest(
            configuration: configuration,
            clientId: "client-id",
            clientSecret: nil,
            scopes: ["email"],
            redirectURL: URL(string: "com.test.app:/oauthredirect")!,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
    }
}
