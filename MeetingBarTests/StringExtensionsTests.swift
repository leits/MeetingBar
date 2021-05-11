import Foundation
import XCTest

@testable import MeetingBar

class StringExtensionsTests: XCTestCase {
    // MARK: withLinksEnabled
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
