//
//  HelpersTests.swift
//  MeetingBarTests
//
//  Created by Andrii Leitsius on 10.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import XCTest
import Defaults
import Security
import UserNotifications

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
}

final class DiagnosticsAdapterTests: BaseTestCase {
    private let knownDate = Date(timeIntervalSince1970: 1_730_000_000)

    func test_providerMappingUsesProductionEventStoreProvider() {
        XCTAssertEqual(DiagnosticsProvider(provider: .macOSEventKit), .macOSEventKit)
        XCTAssertEqual(DiagnosticsProvider(provider: .googleCalendar), .googleCalendar)
    }

    func test_healthMappingCopiesProviderHealthFields() {
        let providerHealth = ProviderHealth(
            lastSuccessfulRefresh: knownDate.addingTimeInterval(-600),
            lastAttemptedRefresh: knownDate,
            lastErrorDescription: "authorization expired",
            isStale: true,
            authRequired: true
        )

        let health = DiagnosticsHealth(health: providerHealth)

        XCTAssertEqual(health.lastSuccessfulRefresh, providerHealth.lastSuccessfulRefresh)
        XCTAssertEqual(health.lastAttemptedRefresh, providerHealth.lastAttemptedRefresh)
        XCTAssertEqual(health.lastErrorDescription, providerHealth.lastErrorDescription)
        XCTAssertTrue(health.isStale)
        XCTAssertTrue(health.authRequired)
    }

    func test_contextMappingFeedsDiagnosticsReport() {
        let context = DiagnosticsContext(
            appVersion: "4.12",
            buildNumber: "999",
            osVersion: "Version 14.5",
            provider: .googleCalendar,
            selectedCalendarCount: 2,
            totalCalendarCount: 5,
            visibleEventCount: 3,
            health: ProviderHealth(
                lastSuccessfulRefresh: nil,
                lastAttemptedRefresh: knownDate,
                lastErrorDescription: "network gone",
                isStale: true,
                authRequired: false
            )
        )

        let report = DiagnosticsReport.text(from: context)

        XCTAssertTrue(report.contains("Provider: Google Calendar"))
        XCTAssertTrue(report.contains("Calendars: 2 selected / 5 available"))
        XCTAssertTrue(report.contains("Visible events: 3"))
        XCTAssertTrue(report.contains("Provider health: error"))
        XCTAssertTrue(report.contains("Last error: network gone"))
    }

    func test_diagnosticsSnapshotUsesAppStateAsItsOnlyRuntimeSource() {
        let event = makeFakeEvent(
            id: "event",
            start: knownDate,
            end: knownDate.addingTimeInterval(1800)
        )
        let health = ProviderHealth(
            lastSuccessfulRefresh: knownDate,
            lastAttemptedRefresh: knownDate,
            isStale: false
        )
        var state = AppState()
        state.activeProvider = .googleCalendar
        state.calendars = [
            makeFakeCalendar(id: "work"),
            makeFakeCalendar(id: "shared")
        ]
        state.selectedCalendarIDs = ["shared"]
        state.events = [event]
        state.providerHealth = health

        let snapshot = DiagnosticsSnapshot(appState: state)

        XCTAssertEqual(snapshot.provider, .googleCalendar)
        XCTAssertEqual(snapshot.selectedCalendarCount, 1)
        XCTAssertEqual(snapshot.totalCalendarCount, 2)
        XCTAssertEqual(snapshot.visibleEventCount, 1)
        XCTAssertEqual(snapshot.health, health)
    }
}

private final class FakeMeetingOpeningPerformer: MeetingOpeningPerforming {
    enum Event: Equatable {
        case script
        case meetingLink(MeetingServices?, URL)
        case eventURL(URL)
        case missingLink(String)
    }

    private(set) var events: [Event] = []

    func runJoinEventScriptIfConfigured() {
        events.append(.script)
    }

    func openMeetingLink(_ service: MeetingServices?, _ url: URL) {
        events.append(.meetingLink(service, url))
    }

    func openEventURL(_ url: URL) {
        events.append(.eventURL(url))
    }

    func notifyMissingLink(title: String) {
        events.append(.missingLink(title))
    }
}

final class MeetingOpenerTests: BaseTestCase {
    func test_performRunsJoinScriptBeforeOpeningMeetingLinkWhenRequested() {
        let performer = FakeMeetingOpeningPerformer()
        let link = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/5551112222")!)

        MeetingOpener.perform(
            .openMeetingLink(link, runJoinScript: true),
            performer: performer
        )

        XCTAssertEqual(performer.events, [
            .script,
            .meetingLink(.zoom, link.url)
        ])
    }

    func test_performSkipsJoinScriptWhenOpeningMeetingLinkWithoutScript() {
        let performer = FakeMeetingOpeningPerformer()
        let link = MeetingLink(service: .meet, url: URL(string: "https://meet.google.com/abc-defg-hij")!)

        MeetingOpener.perform(
            .openMeetingLink(link, runJoinScript: false),
            performer: performer
        )

        XCTAssertEqual(performer.events, [
            .meetingLink(.meet, link.url)
        ])
    }

    func test_performOpensEventURLFallback() {
        let performer = FakeMeetingOpeningPerformer()
        let url = URL(string: "https://calendar.example.test/event")!

        MeetingOpener.perform(.openEventURL(url), performer: performer)

        XCTAssertEqual(performer.events, [.eventURL(url)])
    }

    func test_performNotifiesWhenMeetingLinkIsMissing() {
        let performer = FakeMeetingOpeningPerformer()

        MeetingOpener.perform(.notifyMissingLink(title: "Planning"), performer: performer)

        XCTAssertEqual(performer.events, [.missingLink("Planning")])
    }

    func test_openEventBuildsActionFromEventAndDefaults() {
        Defaults[.runJoinEventScript] = true
        let performer = FakeMeetingOpeningPerformer()
        let event = makeFakeEvent(
            id: "OPEN",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(600),
            withLink: true
        )

        MeetingOpener.open(event: event, performer: performer)

        XCTAssertEqual(performer.events, [
            .script,
            .meetingLink(.zoom, URL(string: "https://zoom.us/j/5551112222")!)
        ])
    }

    func test_detectedTeamsURLsUseTeamsOpeningFlow() throws {
        Defaults[.runJoinEventScript] = false
        let urls = [
            URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!,
            URL(string: "https://teams.microsoft.com/meet/1234567890123?p=Aa1Bb2Cc3Dd4Ee5")!
        ]

        for url in urls {
            let performer = FakeMeetingOpeningPerformer()
            let link = try XCTUnwrap(detectMeetingLink(url.absoluteString))

            XCTAssertEqual(link.service, .teams)
            MeetingOpener.open(meetingLink: link, performer: performer)

            XCTAssertEqual(performer.events, [
                .meetingLink(.teams, url)
            ])
        }
    }

    func test_openMeetingLinkRunsJoinScriptWhenEnabled() {
        Defaults[.runJoinEventScript] = true
        let performer = FakeMeetingOpeningPerformer()
        let link = MeetingLink(service: .meet, url: URL(string: "https://meet.google.com/abc-defg-hij")!)

        MeetingOpener.open(meetingLink: link, performer: performer)

        XCTAssertEqual(performer.events, [
            .script,
            .meetingLink(.meet, link.url)
        ])
    }

    func test_emailAttendeesCollectsNonNilEmails() {
        let attendees: [MBEventAttendee] = [
            MBEventAttendee(email: "alice@example.com", name: "Alice", status: .accepted),
            MBEventAttendee(email: nil, name: "No Email", status: .accepted),
            MBEventAttendee(email: "bob@example.com", name: "Bob", status: .declined)
        ]
        let event = makeFakeEvent(
            id: "EA",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(600),
            withLink: false,
            attendees: attendees
        )
        // emailAttendees opens an NSSharingService, but we can at least verify it does not crash
        // with a mix of nil and non-nil emails. (Real sending is not testable headlessly.)
        MeetingOpener.emailAttendees(for: event)
    }
}

final class MeetingOpenSettingsTests: BaseTestCase {
    private let zoom = Browser(name: "Zoom", path: "")
    private let chrome = Browser(name: "Chrome", path: "/Applications/Google Chrome.app")
    private let safari = Browser(name: "Safari", path: "/Applications/Safari.app")

    private func settings(providerBrowsers: [String: Browser], defaultBrowser: Browser)
        -> MeetingOpenSettings {
        MeetingOpenSettings(
            defaultBrowser: defaultBrowser,
            providerBrowsers: providerBrowsers,
            runJoinEventScript: false,
            joinEventScriptLocation: nil
        )
    }

    private func settings(
        providerBrowsers: [String: Browser],
        providerOpeningModes: [String: String],
        defaultBrowser: Browser
    ) -> MeetingOpenSettings {
        MeetingOpenSettings(
            defaultBrowser: defaultBrowser,
            providerBrowsers: providerBrowsers,
            providerOpeningModes: providerOpeningModes,
            runJoinEventScript: false,
            joinEventScriptLocation: nil
        )
    }

    func test_resolvedBrowserPrefersExplicitOverride() {
        let snapshot = settings(
            providerBrowsers: [MeetingServices.zoom.rawValue: zoom], defaultBrowser: safari)
        // Explicit choice wins over both the per-provider preference and the default.
        XCTAssertEqual(snapshot.resolvedBrowser(for: .zoom, explicit: chrome), chrome)
    }

    func test_resolvedBrowserUsesPerProviderPreferenceWhenNoExplicit() {
        let snapshot = settings(
            providerBrowsers: [MeetingServices.zoom.rawValue: zoom], defaultBrowser: safari)
        XCTAssertEqual(snapshot.resolvedBrowser(for: .zoom, explicit: nil), zoom)
    }

    func test_resolvedBrowserFallsBackToDefaultWhenNoProviderPreference() {
        let snapshot = settings(providerBrowsers: [:], defaultBrowser: safari)
        XCTAssertEqual(snapshot.resolvedBrowser(for: .teams, explicit: nil), safari)
    }

    func test_resolvedBrowserFallsBackToDefaultForNilService() {
        let snapshot = settings(
            providerBrowsers: [MeetingServices.zoom.rawValue: zoom], defaultBrowser: safari)
        XCTAssertEqual(snapshot.resolvedBrowser(for: nil, explicit: nil), safari)
    }

    func test_currentMapsDefaults() {
        Defaults[.defaultBrowser] = chrome
        Defaults[.providerBrowsers] = [MeetingServices.zoom.rawValue: zoom]
        Defaults[.providerOpeningModes] = [
            MeetingServices.zoom.rawValue: MeetingOpeningMode.zoomWebApp.rawValue
        ]
        Defaults[.runJoinEventScript] = true

        let snapshot = MeetingOpenSettings.current
        XCTAssertEqual(snapshot.defaultBrowser, chrome)
        XCTAssertEqual(snapshot.providerBrowsers[MeetingServices.zoom.rawValue], zoom)
        XCTAssertEqual(
            snapshot.providerOpeningModes[MeetingServices.zoom.rawValue],
            MeetingOpeningMode.zoomWebApp.rawValue
        )
        XCTAssertTrue(snapshot.runJoinEventScript)
        // The per-provider preference still resolves through the snapshot.
        XCTAssertEqual(snapshot.resolvedBrowser(for: .zoom, explicit: nil), zoom)
    }

    func test_resolvedOpeningRestoresLegacyNativeAppSentinel() {
        let snapshot = settings(
            providerBrowsers: [MeetingServices.zoom.rawValue: zoomAppBrowser],
            defaultBrowser: safari
        )

        XCTAssertEqual(
            snapshot.resolvedOpening(for: .zoom, explicit: nil),
            ResolvedMeetingOpening(mode: .zoomApp, browser: safari)
        )
    }

    func test_resolvedOpeningKeepsExistingMeetInOneSentinelBehavior() {
        let snapshot = settings(
            providerBrowsers: [MeetingServices.meet.rawValue: meetInOneBrowser],
            defaultBrowser: safari
        )

        XCTAssertEqual(
            snapshot.resolvedOpening(for: .meet, explicit: nil),
            ResolvedMeetingOpening(mode: .meetInOne, browser: safari)
        )
    }

    func test_resolvedOpeningUsesStoredModeAndConfiguredBrowserFallback() {
        let snapshot = settings(
            providerBrowsers: [MeetingServices.zoom.rawValue: chrome],
            providerOpeningModes: [
                MeetingServices.zoom.rawValue: MeetingOpeningMode.zoomWebApp.rawValue
            ],
            defaultBrowser: safari
        )

        XCTAssertEqual(
            snapshot.resolvedOpening(for: .zoom, explicit: nil),
            ResolvedMeetingOpening(mode: .zoomWebApp, browser: chrome)
        )
    }

    func test_resolvedOpeningIgnoresUnknownOrUnsupportedMode() {
        let unknown = settings(
            providerBrowsers: [MeetingServices.zoom.rawValue: chrome],
            providerOpeningModes: [MeetingServices.zoom.rawValue: "removed-mode"],
            defaultBrowser: safari
        )
        let unsupported = settings(
            providerBrowsers: [MeetingServices.zoom.rawValue: chrome],
            providerOpeningModes: [
                MeetingServices.zoom.rawValue: MeetingOpeningMode.googleMeetPWA.rawValue
            ],
            defaultBrowser: safari
        )

        XCTAssertEqual(
            unknown.resolvedOpening(for: .zoom, explicit: nil),
            ResolvedMeetingOpening(mode: nil, browser: chrome)
        )
        XCTAssertEqual(
            unsupported.resolvedOpening(for: .zoom, explicit: nil),
            ResolvedMeetingOpening(mode: nil, browser: chrome)
        )
    }

    func test_explicitBrowserOverridesStoredProviderMode() {
        let snapshot = settings(
            providerBrowsers: [:],
            providerOpeningModes: [
                MeetingServices.meet.rawValue: MeetingOpeningMode.googleMeetPWA.rawValue
            ],
            defaultBrowser: safari
        )

        XCTAssertEqual(
            snapshot.resolvedOpening(for: .meet, explicit: chrome),
            ResolvedMeetingOpening(mode: nil, browser: chrome)
        )
    }

    func test_explicitLegacySentinelKeepsNativeAppBehavior() {
        let snapshot = settings(providerBrowsers: [:], defaultBrowser: safari)

        XCTAssertEqual(
            snapshot.resolvedOpening(for: .teams, explicit: teamsAppBrowser),
            ResolvedMeetingOpening(mode: .teamsApp, browser: safari)
        )
    }
}

final class ProviderOpeningPolicyTests: BaseTestCase {
    private enum TestError: Error {
        case failed
    }

    private final class OpeningSpy: @unchecked Sendable {
        var nativeURLs: [URL] = []
        var browserOpens: [(URL, Browser)] = []
        var defaultURLs: [URL] = []
    }

    func test_workplaceNativeURLPercentEncodesOriginalURL() {
        let original = URL(
            string: "https://workplace.com/groupcall/123?foo=bar&token=a+b#room"
        )!
        let nativeURL = WorkplaceNativeURLPolicy.nativeURL(for: original)

        XCTAssertEqual(nativeURL?.scheme, "workchat")
        XCTAssertEqual(nativeURL?.host, "room")
        XCTAssertEqual(
            URLComponents(
                url: nativeURL!,
                resolvingAgainstBaseURL: false
            )?.queryItems?.first(where: { $0.name == "joinurl" })?.value,
            original.absoluteString
        )
        XCTAssertTrue(nativeURL?.absoluteString.contains("%3A%2F%2F") == true)
        XCTAssertTrue(nativeURL?.absoluteString.contains("%26") == true)
        XCTAssertTrue(nativeURL?.absoluteString.contains("%23") == true)
    }

    func test_workplaceNativeURLRejectsUnsupportedURL() {
        XCTAssertNil(
            WorkplaceNativeURLPolicy.nativeURL(
                for: URL(string: "https://workplace.com/home")!
            )
        )
        XCTAssertNil(
            WorkplaceNativeURLPolicy.nativeURL(
                for: URL(string: "https://example.com/groupcall/123")!
            )
        )
    }

    func test_workplaceNativeFailureFallsBackToOriginalURLInBrowser() {
        let spy = OpeningSpy()
        let original = URL(string: "https://workplace.com/groupcall/123?token=abc")!
        let browser = Browser(name: "Safari", path: "/Applications/Safari.app")
        let strategy = WorkplaceOpenStrategy(
            nativeOpener: {
                spy.nativeURLs.append($0)
                return false
            },
            browserOpener: {
                spy.browserOpens.append(($0, $1))
            }
        )

        strategy.open(
            url: original,
            opening: ResolvedMeetingOpening(mode: .workplaceApp, browser: browser),
            defaultBrowser: systemDefaultBrowser
        )

        XCTAssertEqual(spy.nativeURLs.count, 1)
        XCTAssertEqual(spy.nativeURLs.first?.scheme, "workchat")
        XCTAssertEqual(spy.browserOpens.first?.0, original)
        XCTAssertEqual(spy.browserOpens.first?.1, browser)
    }

    func test_zoomWebAppTransformsMeetingURLAndPreservesQuery() {
        let transformed = ZoomWebAppURLPolicy.webAppURL(
            for: URL(string: "https://company.zoom.us/j/123456789?pwd=abc&uname=Sam")!
        )

        XCTAssertEqual(
            transformed?.absoluteString,
            "https://app.zoom.us/wc/123456789/start?pwd=abc&uname=Sam"
        )
    }

    func test_zoomWebAppRejectsPersonalRoomAndUnsupportedURL() {
        XCTAssertNil(
            ZoomWebAppURLPolicy.webAppURL(
                for: URL(string: "https://zoom.us/my/someone")!
            )
        )
        XCTAssertNil(
            ZoomWebAppURLPolicy.webAppURL(
                for: URL(string: "https://zoom.us/webinar/123456789")!
            )
        )
        XCTAssertNil(
            ZoomWebAppURLPolicy.webAppURL(
                for: URL(string: "https://example.com/j/123456789")!
            )
        )
    }

    func test_googleMeetPWAPlanBuildsChromeArguments() {
        let meetURL = URL(string: "https://meet.google.com/abc-defg-hij?authuser=me")!
        let chromeURL = URL(
            fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        )

        XCTAssertEqual(
            GoogleMeetPWAOpenPolicy.plan(
                for: meetURL,
                chromeExecutableURL: chromeURL,
                pwaAppID: "abcdefghijklmnopabcdefghijklmnop"
            ),
            GoogleMeetPWAOpenPlan(
                executableURL: chromeURL,
                arguments: [
                    "--app-id=abcdefghijklmnopabcdefghijklmnop",
                    "--app-launch-url-for-shortcuts-menu-item=\(meetURL.absoluteString)"
                ]
            )
        )
    }

    func test_googleMeetPWAPlanFallsBackWhenInputOrInstallationIsUnavailable() {
        let meetURL = URL(string: "https://meet.google.com/abc-defg-hij")!
        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome")

        XCTAssertNil(
            GoogleMeetPWAOpenPolicy.plan(
                for: URL(string: "https://example.com/abc-defg-hij")!,
                chromeExecutableURL: chromeURL,
                pwaAppID: "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        XCTAssertNil(
            GoogleMeetPWAOpenPolicy.plan(
                for: meetURL,
                chromeExecutableURL: nil,
                pwaAppID: "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        XCTAssertNil(
            GoogleMeetPWAOpenPolicy.plan(
                for: meetURL,
                chromeExecutableURL: chromeURL,
                pwaAppID: nil
            )
        )
    }

    func test_googleMeetPWALaunchFailureReturnsFalse() {
        let plan = GoogleMeetPWAOpenPlan(
            executableURL: URL(fileURLWithPath: "/missing/chrome"),
            arguments: []
        )

        XCTAssertFalse(
            GoogleMeetPWALauncher.launch(plan) { _ in
                throw TestError.failed
            }
        )
    }

    func test_googleMeetPWAModeFallsBackToOriginalURLWhenLaunchFails() {
        let spy = OpeningSpy()
        let meetURL = URL(string: "https://meet.google.com/abc-defg-hij")!
        let browser = Browser(name: "Safari", path: "/Applications/Safari.app")
        let plan = GoogleMeetPWAOpenPlan(
            executableURL: URL(fileURLWithPath: "/Applications/Google Chrome"),
            arguments: []
        )
        let strategy = GoogleMeetOpenStrategy(
            pwaPlanBuilder: { _ in plan },
            pwaLauncher: { _ in false },
            browserOpener: {
                spy.browserOpens.append(($0, $1))
            },
            defaultOpener: {
                spy.defaultURLs.append($0)
            }
        )

        strategy.open(
            url: meetURL,
            opening: ResolvedMeetingOpening(mode: .googleMeetPWA, browser: browser),
            defaultBrowser: systemDefaultBrowser
        )

        XCTAssertEqual(spy.browserOpens.first?.0, meetURL)
        XCTAssertEqual(spy.browserOpens.first?.1, browser)
        XCTAssertTrue(spy.defaultURLs.isEmpty)
    }

    func test_googleMeetDefaultBrowserAndMeetInOneBehaviorRemainUnchanged() {
        let spy = OpeningSpy()
        let meetURL = URL(string: "https://meet.google.com/abc-defg-hij")!
        let browser = Browser(name: "Safari", path: "/Applications/Safari.app")
        let strategy = GoogleMeetOpenStrategy(
            pwaPlanBuilder: { _ in nil },
            pwaLauncher: { _ in false },
            browserOpener: {
                spy.browserOpens.append(($0, $1))
            },
            defaultOpener: {
                spy.defaultURLs.append($0)
            }
        )

        strategy.open(
            url: meetURL,
            opening: ResolvedMeetingOpening(mode: nil, browser: browser),
            defaultBrowser: systemDefaultBrowser
        )
        strategy.open(
            url: meetURL,
            opening: ResolvedMeetingOpening(mode: .meetInOne, browser: browser),
            defaultBrowser: systemDefaultBrowser
        )

        XCTAssertEqual(spy.browserOpens.first?.0, meetURL)
        XCTAssertEqual(spy.browserOpens.first?.1, browser)
        XCTAssertEqual(
            spy.defaultURLs,
            [URL(string: "meetinone://url=\(meetURL.absoluteString)")!]
        )
    }

    func test_protonMeetUsesDefaultBrowserStrategy() {
        XCTAssertTrue(openStrategy(for: .protonMeet) is DefaultBrowserOpenStrategy)
    }
}

final class ZoomPersonalRoomTests: BaseTestCase {
    private func isPersonal(_ string: String) -> Bool {
        isZoomPersonalRoomURL(URL(string: string)!)
    }

    func test_personalRoomLinksAreDetected() {
        XCTAssertTrue(isPersonal("https://zoom.us/my/username"))
        XCTAssertTrue(isPersonal("https://company.zoom.us/my/username"))
        XCTAssertTrue(isPersonal("https://zoomgov.com/my/person"))
    }

    func test_regularMeetingLinksAreNotPersonalRooms() {
        XCTAssertFalse(isPersonal("https://zoom.us/j/5551112222"))
        XCTAssertFalse(isPersonal("https://company.zoom.us/j/123?pwd=abc"))
    }

    func test_nonZoomLinksAreNotPersonalRooms() {
        XCTAssertFalse(isPersonal("https://meet.google.com/abc-defg-hij"))
        XCTAssertFalse(isPersonal("https://example.com/my/room"))
    }

    func test_personalRoomUsesSingleBrowserDestination() {
        let url = URL(string: "https://company.zoom.us/my/username")!

        XCTAssertEqual(
            zoomWebOpenDestination(for: url, browser: zoomAppBrowser),
            .systemBrowser
        )
    }

    func test_regularMeetingUsesZoomAppDestination() {
        let url = URL(string: "https://zoom.us/j/5551112222?pwd=abc")!

        XCTAssertEqual(
            zoomWebOpenDestination(for: url, browser: zoomAppBrowser),
            .zoomApp(URL(string: "zoommtg://zoom.us/join?confno=5551112222&pwd=abc")!)
        )
    }
}

final class CalendarOpenURLTests: BaseTestCase {
    func test_eventKitEventUsesAppleCalendarURL() {
        XCTAssertEqual(
            eventKitCalendarOpenURL(for: "EVENT-ID"),
            URL(string: "ical://ekevent/EVENT-ID")
        )
    }
}

final class ScriptParameterTests: BaseTestCase {
    func test_scriptParametersContainExpectedFieldCount() {
        let event = makeFakeEvent(
            id: "SP",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(600),
            withLink: true
        )
        let params = createAppleScriptParametersForEvent(event: event)
        // 14 fields: id, title, allDay, start, end, location, recurrent, attendeeCount,
        // meetingURL, service, notes, calendarTitle, calendarSource, attendeesList
        XCTAssertEqual(params.numberOfItems, 14)
    }

    func test_scriptParametersContainEventTitle() {
        let event = makeFakeEvent(
            id: "SP2",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(600),
            withLink: false
        )
        let params = createAppleScriptParametersForEvent(event: event)
        // Items are inserted at index 0 (end-of-list), so first inserted (id) is at index 1,
        // second inserted (title) is at index 2.
        let titleDescriptor = params.atIndex(2)
        XCTAssertEqual(titleDescriptor?.stringValue, event.title)
    }

    func test_scriptParametersUsesEmptyPlaceholderWhenNoMeetingLink() {
        let event = makeFakeEvent(
            id: "SP3",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(600),
            withLink: false
        )
        let params = createAppleScriptParametersForEvent(event: event)
        // When no meeting link, params 9 (meetingURL) and 10 (service) are "EMPTY"
        XCTAssertEqual(params.atIndex(9)?.stringValue, "EMPTY")
        XCTAssertEqual(params.atIndex(10)?.stringValue, "EMPTY")
    }
}

final class KeychainQueryFactoryTests: XCTestCase {
    func test_saveQueryContainsGenericPasswordServiceDataAndAccessibility() {
        let data = Data("token".utf8)
        let query = KeychainQueryFactory.saveQuery(data: data, service: "google")

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "google")
        XCTAssertEqual(query[kSecValueData as String] as? Data, data)
        XCTAssertEqual(
            query[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlock as String
        )
    }

    func test_loadQueryRequestsOneDataItem() {
        let query = KeychainQueryFactory.loadQuery(service: "google")

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "google")
        XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
    }

    func test_deleteQueryTargetsOnlyTheService() {
        let query = KeychainQueryFactory.deleteQuery(service: "google")

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "google")
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertNil(query[kSecReturnData as String])
    }
}

final class SnoozeNotificationRequestFactoryTests: BaseTestCase {
    func test_requestUsesEventTitleAndFixedSnoozeInterval() throws {
        let now = Date()
        let event = makeFakeEvent(
            id: "SNOOZE",
            start: now.addingTimeInterval(900),
            end: now.addingTimeInterval(1800)
        )

        let request = SnoozeNotificationRequestFactory.request(
            event: event,
            interval: .fiveMinuteLater,
            hideMeetingTitle: false,
            now: now
        )

        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(request.identifier, notificationIDs.event_starts)
        XCTAssertEqual(request.content.categoryIdentifier, "SNOOZE_EVENT")
        XCTAssertEqual(request.content.title, event.title)
        XCTAssertEqual(request.content.body, "notifications_event_started_body".loco())
        XCTAssertEqual(request.content.threadIdentifier, "meetingbar")
        XCTAssertEqual(request.content.userInfo["eventID"] as? String, event.id)
        XCTAssertEqual(trigger.timeInterval, 300, accuracy: 0.001)
        XCTAssertFalse(trigger.repeats)
    }

    func test_requestUsesGenericTitleAndTimeUntilStart() throws {
        let now = Date()
        let event = makeFakeEvent(
            id: "SNOOZE_PRIVATE",
            start: now.addingTimeInterval(900),
            end: now.addingTimeInterval(1800)
        )

        let request = SnoozeNotificationRequestFactory.request(
            event: event,
            interval: .untilStart,
            hideMeetingTitle: true,
            now: now
        )

        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(request.content.title, "general_meeting".loco())
        XCTAssertEqual(trigger.timeInterval, 900, accuracy: 0.001)
    }
}

@available(macOS 13.0, *)
final class EventDetailsValueFormatterTests: XCTestCase {
    private func detailedEvent() -> MBEvent {
        let calendar = MBCalendar(
            title: "Product Calendar",
            id: "product",
            source: nil,
            email: nil,
            color: .black
        )
        return MBEvent(
            id: "DETAILS",
            lastModifiedDate: Date(),
            title: "Roadmap review",
            status: .confirmed,
            notes: "Bring launch notes",
            location: "Room 42",
            url: URL(string: "https://zoom.us/j/5551112222"),
            organizer: nil,
            attendees: [
                MBEventAttendee(
                    email: "alice@example.test",
                    name: "Alice",
                    status: .accepted
                ),
                MBEventAttendee(
                    email: nil,
                    name: "Bob",
                    status: .tentative
                )
            ],
            startDate: Date(timeIntervalSince1970: 1_730_000_000),
            endDate: Date(timeIntervalSince1970: 1_730_003_600),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )
    }

    func test_valueFormatsAllNearestEventDetails() {
        let event = detailedEvent()

        XCTAssertEqual(EventDetailsValueFormatter.value(for: .title, event: event), "Roadmap review")
        XCTAssertEqual(EventDetailsValueFormatter.value(for: .calendarTitle, event: event), "Product Calendar")
        XCTAssertEqual(EventDetailsValueFormatter.value(for: .meetingLink, event: event), "https://zoom.us/j/5551112222")
        XCTAssertEqual(EventDetailsValueFormatter.value(for: .meetingService, event: event), "Zoom")
        XCTAssertEqual(EventDetailsValueFormatter.value(for: .url, event: event), "https://zoom.us/j/5551112222")
        XCTAssertEqual(EventDetailsValueFormatter.value(for: .notes, event: event), "Bring launch notes")
        XCTAssertEqual(EventDetailsValueFormatter.value(for: .location, event: event), "Room 42")
        XCTAssertEqual(EventDetailsValueFormatter.value(for: .startDate, event: event), event.startDate.formatted())
        XCTAssertEqual(EventDetailsValueFormatter.value(for: .endDate, event: event), event.endDate.formatted())
        XCTAssertEqual(
            EventDetailsValueFormatter.value(for: .attendees, event: event),
            "Alice <alice@example.test>, Bob <unknown>"
        )
    }
}
