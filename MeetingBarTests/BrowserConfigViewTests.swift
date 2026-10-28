//
//  BrowserConfigViewTests.swift
//  MeetingBarTests
//

import Defaults
import XCTest

@testable import MeetingBar

@MainActor
final class BrowserConfigViewTests: BaseTestCase {
    func testRemovingOneOfTwoSameNamedBrowsersKeepsTheOther() {
        let installed = Browser(name: "Google Chrome", path: "/Applications/Google Chrome.app")
        let installerImage = Browser(name: "Google Chrome", path: "/Volumes/Google Chrome/Google Chrome.app")
        let safari = Browser(name: "Safari", path: "/Applications/Safari.app")
        Defaults[.browsers] = [installed, installerImage, safari]

        BrowserConfigView().removeBrowser(installerImage)

        XCTAssertEqual(Defaults[.browsers], [installed, safari])
    }
}
