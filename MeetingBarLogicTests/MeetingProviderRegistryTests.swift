//
//  MeetingProviderRegistryTests.swift
//  MeetingBarLogicTests
//
//  Verifies that MeetingProviderRegistry is complete and consistent with
//  the existing meetingLinkRegexPatterns dictionary so that migrating
//  detection to the registry in Phase 3 PR 2 cannot silently regress.
//

import XCTest

@testable import MeetingBarLogic

final class MeetingProviderRegistryTests: XCTestCase {
    // MARK: - Completeness

    func testRegistryContainsAllMeetingServicesCases() {
        let missingCases = MeetingServices.allCases.filter {
            MeetingProviderRegistry.descriptor(for: $0) == nil
        }
        XCTAssertTrue(
            missingCases.isEmpty,
            "Registry missing descriptors for: \(missingCases.map(\.rawValue))")
    }

    func testDescriptorIDsAreUnique() {
        let ids = MeetingProviderRegistry.all.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Duplicate descriptor IDs found")
    }

    func testAllDescriptorsHaveNonEmptyID() {
        for descriptor in MeetingProviderRegistry.all {
            XCTAssertFalse(descriptor.id.isEmpty, "Empty ID for descriptor: \(descriptor)")
        }
    }

    func testAllDescriptorsHaveNonEmptyIconName() {
        for descriptor in MeetingProviderRegistry.all {
            XCTAssertFalse(descriptor.iconName.isEmpty, "Empty iconName for \(descriptor.id)")
        }
    }

    func testAllDescriptorsHavePositiveIconDimensions() {
        for descriptor in MeetingProviderRegistry.all {
            XCTAssertGreaterThan(descriptor.iconWidth, 0, "\(descriptor.id) iconWidth must be > 0")
            XCTAssertGreaterThan(
                descriptor.iconHeight, 0, "\(descriptor.id) iconHeight must be > 0")
        }
    }

    // MARK: - Pattern consistency with existing dictionary

    /// Every pattern in meetingLinkRegexPatterns must appear in the registry.
    func testRegistryPatternsMatchExistingDictionary() {
        let registryPatterns = MeetingProviderRegistry.regexPatterns
        for (service, existingPattern) in meetingLinkRegexPatterns {
            let registryPattern = registryPatterns[service]
            XCTAssertEqual(
                registryPattern, existingPattern,
                "Pattern mismatch for \(service.rawValue): registry has \(registryPattern ?? "nil"), existing has \(existingPattern)"
            )
        }
    }

    /// Every pattern in the registry must also appear in meetingLinkRegexPatterns.
    func testExistingDictionaryPatternsMatchRegistry() {
        let registryPatterns = MeetingProviderRegistry.regexPatterns
        for (service, registryPattern) in registryPatterns {
            let existingPattern = meetingLinkRegexPatterns[service]
            XCTAssertEqual(
                existingPattern, registryPattern,
                "Registry has extra pattern for \(service.rawValue) not in meetingLinkRegexPatterns"
            )
        }
    }

    /// Total count must match.
    func testRegistryPatternCountMatchesDictionary() {
        XCTAssertEqual(
            MeetingProviderRegistry.regexPatterns.count,
            meetingLinkRegexPatterns.count,
            "Pattern count mismatch between registry and meetingLinkRegexPatterns"
        )
    }

    // MARK: - Known descriptor values

    func testZoomDescriptor() {
        let desc = MeetingProviderRegistry.descriptor(for: .zoom)
        XCTAssertNotNil(desc)
        XCTAssertEqual(desc?.id, "Zoom")
        XCTAssertEqual(desc?.iconName, "zoom_icon")
        XCTAssertEqual(desc?.iconHeight, 16)
        XCTAssertNotNil(desc?.regexPattern)
    }

    func testGoogleMeetDescriptor() {
        let desc = MeetingProviderRegistry.descriptor(for: .meet)
        XCTAssertNotNil(desc)
        XCTAssertEqual(desc?.iconName, "google_meet_icon")
        if let height = desc?.iconHeight {
            XCTAssertEqual(height, 13.2, accuracy: 0.01)
        } else {
            XCTFail("meet descriptor missing iconHeight")
        }
    }

    func testPhoneDescriptorHasNoPattern() {
        let desc = MeetingProviderRegistry.descriptor(for: .phone)
        XCTAssertNotNil(desc)
        XCTAssertNil(desc?.regexPattern)
    }

    func testFacetimeAudioDescriptorHasNoPattern() {
        let desc = MeetingProviderRegistry.descriptor(for: .facetimeaudio)
        XCTAssertNotNil(desc)
        XCTAssertNil(desc?.regexPattern)
    }

    func testUrlDescriptorHasNoPattern() {
        let desc = MeetingProviderRegistry.descriptor(for: .url)
        XCTAssertNotNil(desc)
        XCTAssertNil(desc?.regexPattern)
    }

    func testOtherDescriptorHasNoPattern() {
        let desc = MeetingProviderRegistry.descriptor(for: .other)
        XCTAssertNotNil(desc)
        XCTAssertNil(desc?.regexPattern)
    }

    func testVenueDescriptorHasSmallIconHeight() {
        let desc = MeetingProviderRegistry.descriptor(for: .venue)
        XCTAssertEqual(desc?.iconHeight, 4)
    }

    func testStringLookupMatchesServiceLookup() {
        for service in MeetingServices.allCases {
            let byService = MeetingProviderRegistry.descriptor(for: service)
            let byString = MeetingProviderRegistry.descriptor(for: service.rawValue)
            XCTAssertEqual(
                byService, byString, "String/service lookup mismatch for \(service.rawValue)")
        }
    }

    // MARK: - Regex validity

    func testAllPatternsAreValidRegexes() throws {
        for descriptor in MeetingProviderRegistry.all {
            guard let pattern = descriptor.regexPattern else { continue }
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: pattern),
                "Invalid regex for \(descriptor.id): \(pattern)"
            )
        }
    }
}
