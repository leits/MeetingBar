//
//  HelpersTests.swift
//  MeetingBarTests
//
//  Created by Andrii Leitsius on 10.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import XCTest

@testable import MeetingBar

class HelpersTests: XCTestCase {
    func test_cleanupOutlookSafeLinks_withSafeLink_returnCleanLink() throws {
        let safeLink = "https://nam12.safelinks.protection.outlook.com/ap/t-59584e83/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_[obfuscated]&data=[obfuscated]"
        let cleanLink = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_[obfuscated]&data=[obfuscated]"

        let result = cleanupOutlookSafeLinks(rawText: safeLink)
        XCTAssertNotNil(result)
        XCTAssertEqual(result, cleanLink)
    }

    func test_cleanupOutlookSafeLinks_witoutSafeLink_returnInput() throws {
        let input = "https://zoom.us/j/5551112222"
        let result = cleanupOutlookSafeLinks(rawText: input)
        XCTAssertNotNil(result)
        XCTAssertEqual(result, input)
    }

    func test_getMatch_withMatch_returnMatch() throws {
        let regex = try! NSRegularExpression(pattern: #"[0-9]{2}"#)
        let result = getMatch(text: "0.11.22.match", regex: regex)
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "11")
    }

    func test_getMatch_withoutMatch_returnNil() throws {
        let regex = try! NSRegularExpression(pattern: #"[0-9]{2}"#)
        let result = getMatch(text: "0.1one1.2two2.match", regex: regex)
        XCTAssertNil(result)
    }

    func test_cleanUpNotes_inputHTML_returnClean() throws {
        let rawNotes = "<p>description</p>"

        let result = cleanUpNotes(rawNotes)
        XCTAssertEqual(result, "description\n")
    }

    func test_cleanUpNotes_inputMeetDivider_returnClean() throws {
        let rawNotes = """
        description
        ──────────
        under divider
        """

        let result = cleanUpNotes(rawNotes)
        XCTAssertEqual(result, "description")
    }

    func test_cleanUpNotes_inputZoomDivider_returnClean() throws {
        let rawNotes = """
        description
        -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
        under divider
        """

        let result = cleanUpNotes(rawNotes)
        XCTAssertEqual(result, "description\n")
    }

    func test_hexStringToUIColor() throws {
        let result = hexStringToUIColor(hex: "#FFFF00")
        XCTAssertEqual(result, NSColor.yellow)
    }

    func test_displayLocation_emptyLocation_returnNil() {
        let event = makeFakeEvent(
            id: "empty-location",
            start: Date(),
            end: Date().addingTimeInterval(60),
            location: " \n\t "
        )

        XCTAssertNil(event.displayLocation)
    }

    func test_displayLocation_normalizesWhitespace() {
        let event = makeFakeEvent(
            id: "room-location",
            start: Date(),
            end: Date().addingTimeInterval(60),
            location: "  Room A\nFloor\t2  "
        )

        XCTAssertEqual(event.displayLocation, "Room A Floor 2")
    }

    func test_displayLocation_urlOnlyLocation_returnNil() {
        let event = makeFakeEvent(
            id: "url-location",
            start: Date(),
            end: Date().addingTimeInterval(60),
            location: "https://zoom.us/j/5551112222"
        )

        XCTAssertNil(event.displayLocation)
    }

    func test_displayLocation_urlOnlyCustomSchemeWithHost_returnNil() {
        let event = makeFakeEvent(
            id: "custom-url-location",
            start: Date(),
            end: Date().addingTimeInterval(60),
            location: "zoommtg://zoom.us/join?action=join&confno=5551112222"
        )

        XCTAssertNil(event.displayLocation)
    }

    func test_displayLocation_urlOnlyPhysicalLocation_returnLocation() {
        let location = "https://maps.example.com/floor/2"
        let event = makeFakeEvent(
            id: "url-only-physical-location",
            start: Date(),
            end: Date().addingTimeInterval(60),
            location: location
        )

        XCTAssertEqual(event.displayLocation, location)
    }

    func test_displayLocation_mixedPhysicalLocationAndUrl_returnLocation() {
        let location = "Room A https://maps.example.com/floor/2"
        let event = makeFakeEvent(
            id: "mixed-location",
            start: Date(),
            end: Date().addingTimeInterval(60),
            location: location
        )

        XCTAssertEqual(event.displayLocation, location)
    }

    func test_displayLocation_urlFirstMixedPhysicalLocation_returnLocation() {
        let location = "https://maps.example.com/floor/2 Room A"
        let event = makeFakeEvent(
            id: "url-first-mixed-location",
            start: Date(),
            end: Date().addingTimeInterval(60),
            location: location
        )

        XCTAssertEqual(event.displayLocation, location)
    }

    func test_displayLocation_hostlessUri_returnLocation() {
        let location = "mailto:frontdesk@example.com"
        let event = makeFakeEvent(
            id: "hostless-location",
            start: Date(),
            end: Date().addingTimeInterval(60),
            location: location
        )

        XCTAssertEqual(event.displayLocation, location)
    }
}
