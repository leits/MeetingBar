//
//  CalendarIconTests.swift
//  MeetingBar
//
//  Copyright © 2026 Andrii Leitsius. All rights reserved.
//

import XCTest
import AppKit
@testable import MeetingBar

@MainActor
final class CalendarIconTests: BaseTestCase {

    private let iconSize = NSSize(width: 16, height: 16)

    private func makeBase(template: Bool = true) -> NSImage {
        let image = NSImage(size: iconSize)
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: iconSize).fill()
        image.unlockFocus()
        image.isTemplate = template
        return image
    }

    private func date(day: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = day
        return Calendar.current.date(from: components)!
    }

    func testReturnsBaseImageWhenShowDateDisabled() {
        let base = makeBase()
        let result = makeCalendarIcon(
            baseImage: base,
            iconFormat: .calendar,
            showDate: false,
            date: date(day: 15),
            size: iconSize
        )
        XCTAssertTrue(result === base, "Should return the base image unchanged when showDate is false")
    }

    func testReturnsBaseImageWhenIconFormatIsAppIcon() {
        let base = makeBase()
        let result = makeCalendarIcon(
            baseImage: base,
            iconFormat: .appicon,
            showDate: true,
            date: date(day: 15),
            size: iconSize
        )
        XCTAssertTrue(result === base, "Should not overlay date when format is .appicon")
    }

    func testReturnsBaseImageWhenIconFormatIsNone() {
        let base = makeBase()
        let result = makeCalendarIcon(
            baseImage: base,
            iconFormat: .none,
            showDate: true,
            date: date(day: 15),
            size: iconSize
        )
        XCTAssertTrue(result === base, "Should not overlay date when format is .none")
    }

    func testReturnsComposedImageWhenEnabledForCalendar() {
        let base = makeBase()
        let result = makeCalendarIcon(
            baseImage: base,
            iconFormat: .calendar,
            showDate: true,
            date: date(day: 15),
            size: iconSize
        )
        XCTAssertFalse(result === base, "Should return a new composed image when overlay is active")
        XCTAssertEqual(result.size, iconSize)
    }

    func testReturnsComposedImageWhenEnabledForEventType() {
        let base = makeBase()
        let result = makeCalendarIcon(
            baseImage: base,
            iconFormat: .eventtype,
            showDate: true,
            date: date(day: 7),
            size: iconSize
        )
        XCTAssertFalse(result === base)
        XCTAssertEqual(result.size, iconSize)
    }

    func testComposedImagePreservesTemplateFlag() {
        let templateBase = makeBase(template: true)
        let templateResult = makeCalendarIcon(
            baseImage: templateBase,
            iconFormat: .calendar,
            showDate: true,
            date: date(day: 1),
            size: iconSize
        )
        XCTAssertTrue(templateResult.isTemplate, "Template flag should propagate so the menu bar tints correctly")

        let nonTemplateBase = makeBase(template: false)
        let nonTemplateResult = makeCalendarIcon(
            baseImage: nonTemplateBase,
            iconFormat: .calendar,
            showDate: true,
            date: date(day: 1),
            size: iconSize
        )
        XCTAssertFalse(nonTemplateResult.isTemplate)
    }

    func testHandlesTwoDigitDay() {
        // Just verifies the two-digit branch doesn't crash and still returns a usable image.
        let base = makeBase()
        let result = makeCalendarIcon(
            baseImage: base,
            iconFormat: .calendar,
            showDate: true,
            date: date(day: 28),
            size: iconSize
        )
        XCTAssertEqual(result.size, iconSize)
    }
}
