//
//  FullscreenNotificationTests.swift
//  MeetingBarTests
//
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import XCTest
import Defaults

@testable import MeetingBar

class FullscreenNotificationTests: BaseTestCase {

    func test_fullscreenNotificationAllScreens_defaultsToFalse() {
        XCTAssertFalse(Defaults[.fullscreenNotificationAllScreens])
    }

    func test_fullscreenNotificationAllScreens_canBeEnabled() {
        Defaults[.fullscreenNotificationAllScreens] = true
        XCTAssertTrue(Defaults[.fullscreenNotificationAllScreens])
    }

    func test_fullscreenNotificationAllScreens_independentOfMainToggle() {
        Defaults[.fullscreenNotification] = false
        Defaults[.fullscreenNotificationAllScreens] = true

        XCTAssertFalse(Defaults[.fullscreenNotification])
        XCTAssertTrue(Defaults[.fullscreenNotificationAllScreens])
    }
}
