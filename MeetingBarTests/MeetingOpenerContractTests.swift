import AppKit
import XCTest

@testable import MeetingBar

@MainActor
final class MeetingOpenerContractTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let defaultBrowser = Browser(name: "System", path: "")
    private let alternateBrowser = Browser(
        name: "Google Chrome", path: "/Applications/Google Chrome.app"
    )

    private func settings(
        script: Bool = false, modes: [String: String] = [:]
    ) -> MeetingOpenSettings {
        MeetingOpenSettings(
            defaultBrowser: defaultBrowser,
            providerBrowsers: [:],
            providerOpeningModes: modes,
            runJoinEventScript: script,
            joinEventScriptLocation: nil
        )
    }

    func testEventOpeningRunsConfiguredScriptBeforeCorrectMeetingLink() throws {
        let event = makeFakeEvent(
            id: "zoom", start: now, end: now.addingTimeInterval(1800), withLink: true
        )
        let recorder = RecordingMeetingOpeningPerformer()

        MeetingOpener.open(event: event, settings: settings(script: true), performer: recorder)

        XCTAssertEqual(recorder.actions, [
            .script("zoom"),
            .meeting(.zoom, URL(string: "https://zoom.us/j/5551112222")!)
        ])
    }

    func testDisabledScriptNeverRunsButMeetingStillOpens() {
        let event = makeFakeEvent(
            id: "zoom", start: now, end: now.addingTimeInterval(1800), withLink: true
        )
        let recorder = RecordingMeetingOpeningPerformer()

        MeetingOpener.open(event: event, settings: settings(), performer: recorder)

        XCTAssertEqual(recorder.actions, [
            .meeting(.zoom, URL(string: "https://zoom.us/j/5551112222")!)
        ])
    }

    func testEventURLFallbackSkipsJoinScript() {
        let fallbackURL = URL(string: "https://calendar.example.test/events/123")!
        let event = MBEvent(
            id: "calendar-only",
            lastModifiedDate: now,
            title: "Planning",
            status: .confirmed,
            notes: nil,
            location: nil,
            url: fallbackURL,
            organizer: nil,
            startDate: now,
            endDate: now.addingTimeInterval(1800),
            isAllDay: false,
            recurrent: false,
            calendar: MBCalendar(
                title: "Work", id: "work", source: nil, email: nil, color: .black
            )
        )
        let recorder = RecordingMeetingOpeningPerformer()

        MeetingOpener.open(event: event, settings: settings(script: true), performer: recorder)

        XCTAssertEqual(recorder.actions, [.eventURL(fallbackURL)])
    }

    func testMissingLinkProducesExplicitNotificationAndNoOpen() {
        let event = makeFakeEvent(
            id: "no-link", start: now, end: now.addingTimeInterval(1800)
        )
        let recorder = RecordingMeetingOpeningPerformer()

        MeetingOpener.open(event: event, settings: settings(script: true), performer: recorder)

        XCTAssertEqual(recorder.actions, [.missing("Event no-link")])
    }

    func testOpenDirectMeetingLinkDoesNotRunJoinScript() {
        let recorder = RecordingMeetingOpeningPerformer()
        let url = URL(string: "https://meet.google.com/abc-defg-hij")!

        MeetingOpener.open(
            meetingLink: MeetingLink(service: .meet, url: url),
            settings: settings(script: true),
            performer: recorder
        )

        XCTAssertEqual(recorder.actions, [.meeting(.meet, url)])
    }

    func testMeetPWAOpenFallsBackToConfiguredBrowserWhenLaunchFails() {
        let recorder = ThreadSafeURLRecorder()
        let url = URL(string: "https://meet.google.com/abc-defg-hij?authuser=work")!
        let applicationURL = URL(fileURLWithPath: "/Applications/Meet.app")
        let strategy = GoogleMeetOpenStrategy(
            pwaPlanBuilder: {
                GoogleMeetPWAOpenPolicy.plan(for: $0, pwaApplicationURL: applicationURL)
            },
            pwaLauncher: { _, completion in completion(false) },
            browserOpener: { opened, browser in
                recorder.record(opened, browser: browser)
            },
            defaultOpener: { _ in XCTFail("Default opener must not be invoked") }
        )

        strategy.open(
            url: url,
            opening: ResolvedMeetingOpening(
                mode: .googleMeetPWA, browser: alternateBrowser
            ),
            defaultBrowser: defaultBrowser
        )

        XCTAssertEqual(recorder.openedURLs, [url])
        XCTAssertEqual(recorder.browserNames, ["Google Chrome"])
    }

    func testMeetPWALaunchSuccessAvoidsDuplicateBrowserOpen() {
        let recorder = ThreadSafeURLRecorder()
        let url = URL(string: "https://meet.google.com/abc-defg-hij")!
        let app = URL(fileURLWithPath: "/Applications/Meet.app")
        let strategy = GoogleMeetOpenStrategy(
            pwaPlanBuilder: {
                GoogleMeetPWAOpenPolicy.plan(for: $0, pwaApplicationURL: app)
            },
            pwaLauncher: { _, completion in completion(true) },
            browserOpener: { opened, browser in recorder.record(opened, browser: browser) },
            defaultOpener: { _ in }
        )

        strategy.open(
            url: url,
            opening: ResolvedMeetingOpening(mode: .googleMeetPWA, browser: alternateBrowser),
            defaultBrowser: defaultBrowser
        )

        XCTAssertTrue(recorder.openedURLs.isEmpty)
    }

    func testMeetPWAMissingAppFallsBackWithoutAttemptingLaunch() {
        let recorder = ThreadSafeURLRecorder()
        let url = URL(string: "https://meet.google.com/abc-defg-hij")!
        let strategy = GoogleMeetOpenStrategy(
            pwaPlanBuilder: { _ in nil },
            pwaLauncher: { _, _ in XCTFail("No installed PWA must not launch") },
            browserOpener: { opened, browser in recorder.record(opened, browser: browser) },
            defaultOpener: { _ in }
        )

        strategy.open(
            url: url,
            opening: ResolvedMeetingOpening(mode: .googleMeetPWA, browser: alternateBrowser),
            defaultBrowser: defaultBrowser
        )

        XCTAssertEqual(recorder.openedURLs, [url])
        XCTAssertEqual(recorder.browserNames, ["Google Chrome"])
    }

    func testProviderOpeningModeKeepsSelectedBrowserForFallback() {
        let selected = MeetingOpenSettings(
            defaultBrowser: defaultBrowser,
            providerBrowsers: [.meet.rawValue: alternateBrowser],
            providerOpeningModes: [
                MeetingServices.meet.rawValue: MeetingOpeningMode.googleMeetPWA.rawValue
            ],
            runJoinEventScript: false,
            joinEventScriptLocation: nil
        )

        let opening = selected.resolvedOpening(for: .meet, explicit: nil)
        XCTAssertEqual(opening.mode, .googleMeetPWA)
        XCTAssertEqual(opening.browser, alternateBrowser)
    }
}

private final class RecordingMeetingOpeningPerformer: MeetingOpeningPerforming {
    enum Action: Equatable {
        case script(String)
        case meeting(MeetingServices?, URL)
        case eventURL(URL)
        case missing(String)
    }

    private(set) var actions: [Action] = []

    func runJoinEventScriptIfConfigured(event: MBEvent) {
        actions.append(.script(event.id))
    }

    func openMeetingLink(_ service: MeetingServices?, _ url: URL) {
        actions.append(.meeting(service, url))
    }

    func openEventURL(_ url: URL) {
        actions.append(.eventURL(url))
    }

    func notifyMissingLink(title: String) {
        actions.append(.missing(title))
    }
}

private final class ThreadSafeURLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var names: [String] = []

    func record(_ url: URL, browser: Browser) {
        lock.lock()
        urls.append(url)
        names.append(browser.name)
        lock.unlock()
    }

    var openedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    var browserNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return names
    }
}
