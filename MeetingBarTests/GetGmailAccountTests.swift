//
//  GetGmailAccountTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class GetGmailAccountTests: XCTestCase {
    func testExtractsEmailFromMailtoQuotes() {
        let source = #"<EKSource: ID="abc"; "mailto:user@example.com"; type=2>"#
        XCTAssertEqual(getGmailAccount(source), "user@example.com")
    }

    func testReturnsNilWhenNoMailtoFound() {
        XCTAssertNil(getGmailAccount("<EKSource: ID=\"abc\"; type=2>"))
    }

    func testReturnsNilOnEmptyString() {
        XCTAssertNil(getGmailAccount(""))
    }

    func testReturnsFirstMailtoWhenMultiplePresent() {
        let source = #""mailto:first@example.com" something "mailto:second@example.com""#
        XCTAssertEqual(getGmailAccount(source), "first@example.com")
    }

    func testHandlesEmailWithSubdomain() {
        let source = #""mailto:user@mail.corp.example.com""#
        XCTAssertEqual(getGmailAccount(source), "user@mail.corp.example.com")
    }
}
