//
//  NextEventTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

@testable import MeetingBar
import XCTest

/// Make sure this lives in your test target, and that
/// all your test cases subclass BaseTestCase so they
/// don’t touch the real Defaults.
class NextEventTests: XCTestCase {
    /// Shortcut to “now” so all offsets are relative.
    private let now = Date()

    func test_picksSoonestFutureEvent() {
        let e1 = makeFakeEvent(
            id: "1",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(360),
            withLink: true
        )
        let e2 = makeFakeEvent(
            id: "2",
            start: now.addingTimeInterval(100),
            end: now.addingTimeInterval(160),
            withLink: true
        )

        let array = [e1, e2]
        XCTAssertEqual(array.nextEvent(), e2)
    }

    func test_skipsEventsWithoutLink_whenLinkRequired() {
        let noLink = makeFakeEvent(
            id: "A",
            start: now.addingTimeInterval(50),
            end: now.addingTimeInterval(100),
            withLink: false
        )
        let withLink = makeFakeEvent(
            id: "B",
            start: now.addingTimeInterval(150),
            end: now.addingTimeInterval(200),
            withLink: true
        )

        let array = [noLink, withLink]
        XCTAssertEqual(array.nextEvent(linkRequired: true), withLink)
    }

    func test_returnsNil_ifAllCandidatesLackLink_andLinkRequired() {
        let a = makeFakeEvent(
            id: "X",
            start: now.addingTimeInterval(100),
            end: now.addingTimeInterval(200),
            withLink: false
        )
        let b = makeFakeEvent(
            id: "Y",
            start: now.addingTimeInterval(200),
            end: now.addingTimeInterval(300),
            withLink: false
        )

        XCTAssertNil([a, b].nextEvent(linkRequired: true))
    }

    func test_skipsCanceled_andDeclinedEvents() {
        let good = makeFakeEvent(
            id: "G",
            start: now.addingTimeInterval(100),
            end: now.addingTimeInterval(160),
            withLink: true
        )
        let canceled = makeFakeEvent(
            id: "C",
            start: now.addingTimeInterval(50),
            end: now.addingTimeInterval(110),
            status: .canceled,
            withLink: true
        )
        let declined = makeFakeEvent(
            id: "D",
            start: now.addingTimeInterval(10),
            end: now.addingTimeInterval(70),
            withLink: true,
            participationStatus: .declined
        )

        let array = [declined, canceled, good]
        XCTAssertEqual(array.nextEvent(), good)
    }

    func test_prefersRunningEvent_ifNowBetweenStartAndEnd() {
        let running = makeFakeEvent(
            id: "R",
            start: now.addingTimeInterval(-600),
            end: now.addingTimeInterval(600),
            withLink: true
        )
        let future = makeFakeEvent(
            id: "F",
            start: now.addingTimeInterval(500),
            end: now.addingTimeInterval(800),
            withLink: true
        )

        // even though `future` is technically sooner in time,
        // our business rule picks an event that's already started
        let array = [future, running]
        XCTAssertEqual(array.nextEvent(), running)
    }
}
