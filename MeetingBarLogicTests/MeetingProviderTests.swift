//
//  MeetingProviderTests.swift
//  MeetingBarLogicTests
//
//  Verifies that MeetingProvider catalogue is complete and consistent with
//  the existing meetingLinkRegexPatterns dictionary so that migrating
//  detection to the registry in Phase 3 PR 2 cannot silently regress.
//

import XCTest

@testable import MeetingBarLogic

final class MeetingProviderTests: XCTestCase {
    // MARK: - Completeness

    func testRegistryContainsAllMeetingServicesCases() {
        let missingCases = MeetingServices.allCases.filter {
            MeetingProvider.provider(for: $0) == nil
        }
        XCTAssertTrue(
            missingCases.isEmpty,
            "Registry missing descriptors for: \(missingCases.map(\.rawValue))")
    }

    func testDescriptorIDsAreUnique() {
        let ids = MeetingProvider.all.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Duplicate descriptor IDs found")
    }

    func testAllDescriptorsHaveNonEmptyID() {
        for descriptor in MeetingProvider.all {
            XCTAssertFalse(descriptor.id.isEmpty, "Empty ID for descriptor: \(descriptor)")
        }
    }

    func testAllDescriptorsHaveNonEmptyIconName() {
        for descriptor in MeetingProvider.all {
            XCTAssertFalse(descriptor.iconName.isEmpty, "Empty iconName for \(descriptor.id)")
        }
    }

    func testAllDescriptorsHavePositiveIconDimensions() {
        for descriptor in MeetingProvider.all {
            XCTAssertGreaterThan(descriptor.iconWidth, 0, "\(descriptor.id) iconWidth must be > 0")
            XCTAssertGreaterThan(
                descriptor.iconHeight, 0, "\(descriptor.id) iconHeight must be > 0")
        }
    }

    // MARK: - Known descriptor values

    func testZoomDescriptor() {
        let desc = MeetingProvider.provider(for: .zoom)
        XCTAssertNotNil(desc)
        XCTAssertEqual(desc?.id, "Zoom")
        XCTAssertEqual(desc?.iconName, "zoom_icon")
        XCTAssertEqual(desc?.iconHeight, 16)
        XCTAssertNotNil(desc?.regexPattern)
    }

    func testGoogleMeetDescriptor() {
        let desc = MeetingProvider.provider(for: .meet)
        XCTAssertNotNil(desc)
        XCTAssertEqual(desc?.iconName, "google_meet_icon")
        XCTAssertEqual(desc?.openingModes, [.meetInOne, .googleMeetPWA])
        if let height = desc?.iconHeight {
            XCTAssertEqual(height, 13.2, accuracy: 0.01)
        } else {
            XCTFail("meet descriptor missing iconHeight")
        }
    }

    func testProviderSpecificOpeningModes() {
        XCTAssertEqual(
            MeetingProvider.provider(for: .zoom)?.openingModes,
            [.zoomApp, .zoomWebApp]
        )
        XCTAssertEqual(
            MeetingProvider.provider(for: .teams)?.openingModes,
            [.teamsApp]
        )
        XCTAssertEqual(
            MeetingProvider.provider(for: .facebook_workspace)?.openingModes,
            [.workplaceApp]
        )
        XCTAssertEqual(
            MeetingProvider.provider(for: .facebook_workspace)?.displayName,
            "Workplace"
        )
    }

    func testProtonMeetDescriptorUsesFallbackIconAndNoOpeningModes() {
        let descriptor = MeetingProvider.provider(for: .protonMeet)

        XCTAssertEqual(descriptor?.iconName, "no_online_session")
        XCTAssertNotNil(descriptor?.regexPattern)
        XCTAssertEqual(descriptor?.openingModes, [])
    }

    func testPhoneDescriptorHasNoPattern() {
        let desc = MeetingProvider.provider(for: .phone)
        XCTAssertNotNil(desc)
        XCTAssertNil(desc?.regexPattern)
    }

    func testFacetimeAudioDescriptorHasNoPattern() {
        let desc = MeetingProvider.provider(for: .facetimeaudio)
        XCTAssertNotNil(desc)
        XCTAssertNil(desc?.regexPattern)
    }

    func testUrlDescriptorHasNoPattern() {
        let desc = MeetingProvider.provider(for: .url)
        XCTAssertNotNil(desc)
        XCTAssertNil(desc?.regexPattern)
    }

    func testOtherDescriptorHasNoPattern() {
        let desc = MeetingProvider.provider(for: .other)
        XCTAssertNotNil(desc)
        XCTAssertNil(desc?.regexPattern)
    }

    func testVenueDescriptorHasSmallIconHeight() {
        let desc = MeetingProvider.provider(for: .venue)
        XCTAssertEqual(desc?.iconHeight, 4)
    }

    func testStringLookupMatchesServiceLookup() {
        for service in MeetingServices.allCases {
            let byService = MeetingProvider.provider(for: service)
            let byString = MeetingProvider.provider(for: service.rawValue)
            XCTAssertEqual(
                byService, byString, "String/service lookup mismatch for \(service.rawValue)")
        }
    }

    func testDescriptorForUnknownStringReturnsNil() {
        XCTAssertNil(MeetingProvider.provider(for: "__unknown_service__"))
    }

    // MARK: - Regex validity

    func testAllPatternsAreValidRegexes() throws {
        for descriptor in MeetingProvider.all {
            guard let pattern = descriptor.regexPattern else { continue }
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: pattern),
                "Invalid regex for \(descriptor.id): \(pattern)"
            )
        }
    }
}
