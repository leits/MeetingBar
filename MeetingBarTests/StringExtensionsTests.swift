import Foundation
import XCTest

@testable import MeetingBar

class StringExtensionsTests: XCTestCase {
    private var temporaryBundles: [URL] = []

    override func tearDown() {
        for url in temporaryBundles {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryBundles.removeAll()
        super.tearDown()
    }

    func testLocalizedStringFallsBackToEnglishWhenSelectedLocaleMissesKey() throws {
        let selectedBundle = try makeLocalizationBundle(
            identifier: "selected",
            strings: ["translated_key": "Translated"]
        )
        let englishBundle = try makeLocalizationBundle(
            identifier: "english",
            strings: ["fallback_key": "English fallback"]
        )
        let i18n = I18N(
            bundle: selectedBundle,
            englishBundle: englishBundle,
            locale: Locale(identifier: "de")
        )

        XCTAssertEqual(i18n.localizedString(for: "fallback_key"), "English fallback")
    }

    // MARK: withLinksEnabled

    private func makeLocalizationBundle(
        identifier: String,
        strings: [String: String]
    ) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("\(identifier).bundle")
        temporaryBundles.append(root.deletingLastPathComponent())
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(
            at: resources,
            withIntermediateDirectories: true
        )

        let infoData = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "test.\(identifier)"],
            format: .xml,
            options: 0
        )
        try infoData.write(to: root.appendingPathComponent("Contents/Info.plist"))

        let stringsData = try PropertyListSerialization.data(
            fromPropertyList: strings,
            format: .xml,
            options: 0
        )
        try stringsData.write(to: resources.appendingPathComponent("Localizable.strings"))

        return try XCTUnwrap(Bundle(url: root))
    }

    func testLinkDetectionPicksUpHttpDotComLinks() throws {
        let urlString = "http://example.com"
        let testString = NSAttributedString(string: "\(urlString)")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpHttpDotComLinksSubstring() throws {
        let urlString = "http://example.com"
        let testString = NSAttributedString(string: "prefix \(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpHttpDotComLinksSubstringNoSpacePrefix() throws {
        let urlString = "http://example.com"
        let testString = NSAttributedString(string: "prefix\(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpHttpDotComLinksSubstringWithQueryParams() throws {
        let urlString = "http://example.com?exampleParam=true&anotherParam=12498"
        let testString = NSAttributedString(string: "prefix \(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpHttpsDotComLinks() throws {
        let urlString = "https://example.com"
        let testString = NSAttributedString(string: "\(urlString)")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpHttpsDotComLinksSubstring() throws {
        let urlString = "https://example.com"
        let testString = NSAttributedString(string: "prefix \(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpHttpsDotComLinksSubstringNoSpacePrefix() throws {
        let urlString = "https://example.com"
        let testString = NSAttributedString(string: "prefix\(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpHttpsDotComLinksSubstringWithQueryParams() throws {
        let urlString = "https://example.com?exampleParam=true&anotherParam=12498"
        let testString = NSAttributedString(string: "prefix \(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpHttpsDotIoLinksSubstringWithQueryParams() throws {
        let urlString = "https://example.io?exampleParam=true&anotherParam=12498"
        let testString = NSAttributedString(string: "prefix \(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpIPAddressLinksSubstring() throws {
        let urlString = "https://127.0.0.1"
        let testString = NSAttributedString(string: "prefix \(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }

    func testLinkDetectionPicksUpIPAddressLinksSubstringWithPort() throws {
        let urlString = "https://127.0.0.1:9001"
        let testString = NSAttributedString(string: "prefix \(urlString) suffix")
        let expectedRange = NSRange(location: 0, length: testString.string.utf16.count)
        let resultString = testString.withLinksEnabled()

        resultString.enumerateAttributes(in: expectedRange) { attrDict, range, _ in
            if let linkAttr = attrDict[.link] as? URL {
                XCTAssert(expectedRange.intersection(range)?.length ?? 0 > 0)
                XCTAssert(linkAttr.absoluteString == urlString)
            }
        }
    }
}
