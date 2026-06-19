//
//  MeetingOpener.swift
//  MeetingBar
//

import AppKit
import Defaults

struct ResolvedMeetingOpening: Equatable {
    let mode: MeetingOpeningMode?
    let browser: Browser
}

/// Value snapshot of the settings the opening path needs: per-provider browser
/// preferences and the join-event script configuration.
///
/// `current` is the single place opening-related `Defaults` are read; the
/// strategies, performer, and `MeetingOpener.open` all receive this snapshot
/// instead of reaching into `Defaults` themselves. This collapses what used to
/// be ~20 scattered `Defaults[…]` reads into one boundary.
struct MeetingOpenSettings {
    var defaultBrowser: Browser
    var providerBrowsers: [String: Browser]
    var providerOpeningModes: [String: String]
    var runJoinEventScript: Bool
    var joinEventScriptLocation: URL?

    init(
        defaultBrowser: Browser,
        providerBrowsers: [String: Browser],
        providerOpeningModes: [String: String] = [:],
        runJoinEventScript: Bool,
        joinEventScriptLocation: URL?
    ) {
        self.defaultBrowser = defaultBrowser
        self.providerBrowsers = providerBrowsers
        self.providerOpeningModes = providerOpeningModes
        self.runJoinEventScript = runJoinEventScript
        self.joinEventScriptLocation = joinEventScriptLocation
    }

    /// Resolves which browser to use for a service: an explicit override wins,
    /// then the per-provider preference, then the app-wide default browser.
    func resolvedBrowser(for service: MeetingServices?, explicit: Browser?) -> Browser {
        if let explicit { return explicit }
        if let service, let preferred = providerBrowsers[service.rawValue] { return preferred }
        return defaultBrowser
    }

    func resolvedOpening(
        for service: MeetingServices?,
        explicit browser: Browser?
    ) -> ResolvedMeetingOpening {
        if let browser {
            if let service,
               let provider = MeetingProvider.provider(for: service),
               let mode = legacyOpeningMode(for: provider, browser: browser) {
                return ResolvedMeetingOpening(mode: mode, browser: defaultBrowser)
            }
            return ResolvedMeetingOpening(mode: nil, browser: browser)
        }
        guard let service,
              let provider = MeetingProvider.provider(for: service)
        else {
            return ResolvedMeetingOpening(mode: nil, browser: defaultBrowser)
        }

        let providerBrowser = providerBrowsers[provider.id]
        let fallbackBrowser = providerBrowser.flatMap {
            legacyOpeningMode(for: provider, browser: $0) == nil ? $0 : nil
        } ?? defaultBrowser

        if let storedID = providerOpeningModes[provider.id],
           let mode = MeetingOpeningMode(rawValue: storedID),
           provider.openingModes.contains(mode) {
            return ResolvedMeetingOpening(mode: mode, browser: fallbackBrowser)
        }
        if let providerBrowser,
           let mode = legacyOpeningMode(for: provider, browser: providerBrowser) {
            return ResolvedMeetingOpening(mode: mode, browser: defaultBrowser)
        }
        return ResolvedMeetingOpening(mode: nil, browser: fallbackBrowser)
    }

    static var current: MeetingOpenSettings {
        MeetingOpenSettings(
            defaultBrowser: Defaults[.defaultBrowser],
            providerBrowsers: Defaults[.providerBrowsers],
            providerOpeningModes: Defaults[.providerOpeningModes],
            runJoinEventScript: Defaults[.runJoinEventScript],
            joinEventScriptLocation: Defaults[.joinEventScriptLocation]
        )
    }
}

func legacyOpeningMode(
    for provider: MeetingProvider,
    browser: Browser
) -> MeetingOpeningMode? {
    guard browser.path.isEmpty else { return nil }
    return provider.openingModes.first {
        $0.legacyBrowserName == browser.name
    }
}

protocol MeetingOpeningPerforming {
    func runJoinEventScriptIfConfigured(event: MBEvent)
    func openMeetingLink(_ service: MeetingServices?, _ url: URL)
    func openEventURL(_ url: URL)
    func notifyMissingLink(title: String)
}

struct SystemMeetingOpeningPerformer: MeetingOpeningPerforming {
    var settings: MeetingOpenSettings

    func runJoinEventScriptIfConfigured(event: MBEvent) {
        guard settings.runJoinEventScript,
              let scriptLocation = settings.joinEventScriptLocation,
              event.meetingLink != nil
        else { return }
        let scriptURL = scriptLocation.appendingPathComponent("joinEventScript.scpt")
        let task: NSUserAppleScriptTask
        do {
            task = try NSUserAppleScriptTask(url: scriptURL)
        } catch {
            AppMessageCenter.shared.post(
                .joinScriptFailed(description: error.localizedDescription)
            )
            return
        }

        // Join hooks use the same documented event payload contract as
        // event-start hooks.
        let appleEvent = createAppleScriptEvent(event: event, type: .meetingStart)
        task.execute(withAppleEvent: appleEvent) { _, error in
            if let error {
                AppMessageCenter.shared.post(
                    .joinScriptFailed(description: error.localizedDescription)
                )
            }
        }
    }

    func openMeetingLink(_ service: MeetingServices?, _ url: URL) {
        openMeetingURL(service, url, nil, settings: settings)
    }

    func openEventURL(_ url: URL) {
        url.openInDefaultBrowser()
    }

    func notifyMissingLink(title: String) {
        AppMessageCenter.shared.post(.meetingLinkMissing(title: title))
    }
}

/// Opens a meeting for a given event or performs email-attendees actions.
/// `MBEvent` is now a data-only struct; all opening side effects live here.
enum MeetingOpener {
    static func open(
        event: MBEvent,
        settings: MeetingOpenSettings = .current,
        performer: (any MeetingOpeningPerforming)? = nil
    ) {
        let action = MeetingOpeningPolicy.action(
            for: MeetingOpeningEvent(
                title: event.title,
                meetingLink: event.meetingLink,
                eventURL: event.url
            ),
            runJoinEventScript: settings.runJoinEventScript
        )

        perform(
            action,
            event: event,
            performer: performer ?? SystemMeetingOpeningPerformer(settings: settings)
        )
    }

    static func open(
        meetingLink: MeetingLink,
        settings: MeetingOpenSettings = .current,
        performer: (any MeetingOpeningPerforming)? = nil
    ) {
        perform(
            .openMeetingLink(meetingLink, runJoinScript: false),
            performer: performer ?? SystemMeetingOpeningPerformer(settings: settings)
        )
    }

    static func emailAttendees(for event: MBEvent) {
        let service = NSSharingService(named: NSSharingService.Name.composeEmail)!
        var recipients: [String] = []
        for attendee in event.attendees {
            if let email = attendee.email {
                recipients.append(email)
            }
        }
        service.recipients = recipients
        service.subject = event.title
        service.perform(withItems: [])
    }

    static func perform(
        _ action: MeetingOpeningAction,
        event: MBEvent? = nil,
        performer: any MeetingOpeningPerforming
    ) {
        switch action {
        case let .openMeetingLink(meetingLink, runJoinScript):
            if runJoinScript, let event {
                performer.runJoinEventScriptIfConfigured(event: event)
            }
            performer.openMeetingLink(meetingLink.service, meetingLink.url)
        case let .openEventURL(eventURL):
            performer.openEventURL(eventURL)
        case let .notifyMissingLink(title):
            performer.notifyMissingLink(title: title)
        }
    }
}

// MARK: - Open strategies (per-provider URL transforms)

/// Encapsulates how a meeting provider URL should be opened.
///
/// `opening` contains an optional provider mode and the resolved browser
/// fallback. `defaultBrowser` is retained for legacy strategies whose existing
/// fallback behavior uses the app-wide default.
protocol MeetingOpenStrategy: Sendable {
    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser: Browser
    )
}

/// Opens the URL in the resolved browser.
struct DefaultBrowserOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser _: Browser
    ) {
        url.openIn(browser: opening.browser)
    }
}

/// Opens via a native-only URL scheme (e.g. `facetime://`, `tel://`).
struct NativeSchemeOpenStrategy: MeetingOpenStrategy, Sendable {
    let schemePrefix: String

    func open(
        url: URL,
        opening _: ResolvedMeetingOpening,
        defaultBrowser _: Browser
    ) {
        guard let nativeURL = URL(string: schemePrefix + url.absoluteString) else { return }
        NSWorkspace.shared.open(nativeURL)
    }
}

/// Handles `zoommtg://` links: tries the app, falls back to an https URL if
/// the app is missing.
struct ZoomNativeOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(
        url: URL,
        opening _: ResolvedMeetingOpening,
        defaultBrowser _: Browser
    ) {
        let result = url.openInDefaultBrowser()
        if !result {
            AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Zoom"))
            let urlString = url.absoluteString
                .replacingFirstOccurrence(of: "&", with: "?")
                .replacingOccurrences(of: "/join?confno=", with: "/j/")
            var fallback = URLComponents(
                url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            fallback.scheme = "https"
            fallback.url?.openInDefaultBrowser()
        }
    }
}

struct GoogleMeetPWAOpenPlan: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
}

enum GoogleMeetPWAOpenPolicy {
    static func plan(
        for url: URL,
        chromeExecutableURL: URL?,
        pwaAppID: String?
    ) -> GoogleMeetPWAOpenPlan? {
        guard url.scheme == "https",
              url.host?.lowercased() == "meet.google.com",
              url.pathComponents.count >= 2,
              let chromeExecutableURL,
              let pwaAppID,
              pwaAppID.count == 32,
              pwaAppID.allSatisfy({ ("a" ... "p").contains($0) })
        else { return nil }

        return GoogleMeetPWAOpenPlan(
            executableURL: chromeExecutableURL,
            arguments: [
                "--app-id=\(pwaAppID)",
                "--app-launch-url-for-shortcuts-menu-item=\(url.absoluteString)"
            ]
        )
    }
}

enum GoogleMeetPWAInstallation {
    static func chromeExecutableURL(
        fileManager: FileManager = .default
    ) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
            home.appendingPathComponent(
                "Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func appID(fileManager: FileManager = .default) -> String? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(
                "Applications/Chrome Apps.localized/Google Meet.app"),
            home.appendingPathComponent(
                "Applications/Chrome Apps/Google Meet.app"),
            URL(fileURLWithPath: "/Applications/Chrome Apps.localized/Google Meet.app"),
            URL(fileURLWithPath: "/Applications/Chrome Apps/Google Meet.app")
        ]

        for appURL in candidates where fileManager.fileExists(atPath: appURL.path) {
            if let appID = Bundle(url: appURL)?
                .object(forInfoDictionaryKey: "CrAppModeShortcutID") as? String,
               !appID.isEmpty {
                return appID
            }
        }
        return nil
    }
}

enum GoogleMeetPWALauncher {
    static func launch(_ plan: GoogleMeetPWAOpenPlan) -> Bool {
        launch(plan, processRunner: runProcess)
    }

    static func launch(
        _ plan: GoogleMeetPWAOpenPlan,
        processRunner: (GoogleMeetPWAOpenPlan) throws -> Void
    ) -> Bool {
        do {
            try processRunner(plan)
            return true
        } catch {
            AppMessageCenter.shared.post(.browserUnavailable(name: "Google Chrome"))
            return false
        }
    }

    private static func runProcess(_ plan: GoogleMeetPWAOpenPlan) throws {
        let process = Process()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments
        try process.run()
    }
}

/// Opens Google Meet links in the selected browser, MeetInOne, or the
/// installed Chrome Google Meet PWA.
struct GoogleMeetOpenStrategy: MeetingOpenStrategy, Sendable {
    private let pwaPlanBuilder: @Sendable (URL) -> GoogleMeetPWAOpenPlan?
    private let pwaLauncher: @Sendable (GoogleMeetPWAOpenPlan) -> Bool
    private let browserOpener: @Sendable (URL, Browser) -> Void
    private let defaultOpener: @Sendable (URL) -> Void

    init(
        pwaPlanBuilder: @escaping @Sendable (URL) -> GoogleMeetPWAOpenPlan? = {
            GoogleMeetPWAOpenPolicy.plan(
                for: $0,
                chromeExecutableURL: GoogleMeetPWAInstallation.chromeExecutableURL(),
                pwaAppID: GoogleMeetPWAInstallation.appID()
            )
        },
        pwaLauncher: @escaping @Sendable (GoogleMeetPWAOpenPlan) -> Bool = {
            GoogleMeetPWALauncher.launch($0)
        },
        browserOpener: @escaping @Sendable (URL, Browser) -> Void = {
            $0.openIn(browser: $1)
        },
        defaultOpener: @escaping @Sendable (URL) -> Void = {
            $0.openInDefaultBrowser()
        }
    ) {
        self.pwaPlanBuilder = pwaPlanBuilder
        self.pwaLauncher = pwaLauncher
        self.browserOpener = browserOpener
        self.defaultOpener = defaultOpener
    }

    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser _: Browser
    ) {
        switch opening.mode {
        case .meetInOne:
            let meetInOneURL = URL(string: "meetinone://url=" + url.absoluteString)!
            defaultOpener(meetInOneURL)
        case .googleMeetPWA:
            guard let plan = pwaPlanBuilder(url), pwaLauncher(plan) else {
                browserOpener(url, opening.browser)
                return
            }
        case .zoomApp, .zoomWebApp, .teamsApp, .workplaceApp, .jitsiApp,
             .slackApp, .riversideApp, nil:
            browserOpener(url, opening.browser)
        }
    }
}

/// Extracts the Slack team/huddle IDs from the https URL and opens the
/// native `slack://join-huddle` deep link, falling back to browser.
struct SlackHuddleOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser: Browser
    ) {
        if opening.mode == .slackApp {
            let components = url.pathComponents
            guard components.count >= 4 else {
                url.openIn(browser: defaultBrowser)
                return
            }
            let teamID = components[2]
            let huddleID = components[3]
            guard let slackURL = URL(string: "slack://join-huddle?team=\(teamID)&id=\(huddleID)")
            else {
                url.openIn(browser: defaultBrowser)
                return
            }
            let result = slackURL.openInDefaultBrowser()
            if !result {
                AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Slack"))
                url.openIn(browser: defaultBrowser)
            }
        } else {
            url.openIn(browser: opening.browser)
        }
    }
}

/// Tries `riversidefm://` then `riverside.fm://` before falling back to browser.
struct RiversideOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser: Browser
    ) {
        if opening.mode == .riversideApp {
            for scheme in ["riversidefm", "riverside.fm"] {
                guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                else { continue }
                components.scheme = scheme
                if let appURL = components.url, appURL.openInDefaultBrowser() { return }
            }
            AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Riverside"))
            url.openIn(browser: defaultBrowser)
        } else {
            url.openIn(browser: opening.browser)
        }
    }
}

enum WorkplaceNativeURLPolicy {
    static func nativeURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == "workplace.com" || host.hasSuffix(".workplace.com"),
              url.path.hasPrefix("/groupcall/"),
              url.pathComponents.count >= 3
        else { return nil }

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encodedURL = url.absoluteString.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) else { return nil }
        return URL(string: "workchat://room/?joinurl=\(encodedURL)")
    }
}

struct WorkplaceOpenStrategy: MeetingOpenStrategy, Sendable {
    private let nativeOpener: @Sendable (URL) -> Bool
    private let browserOpener: @Sendable (URL, Browser) -> Void

    init(
        nativeOpener: @escaping @Sendable (URL) -> Bool = {
            $0.openInDefaultBrowser()
        },
        browserOpener: @escaping @Sendable (URL, Browser) -> Void = {
            $0.openIn(browser: $1)
        }
    ) {
        self.nativeOpener = nativeOpener
        self.browserOpener = browserOpener
    }

    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser _: Browser
    ) {
        guard opening.mode == .workplaceApp,
              let nativeURL = WorkplaceNativeURLPolicy.nativeURL(for: url)
        else {
            browserOpener(url, opening.browser)
            return
        }

        guard nativeOpener(nativeURL) else {
            AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Workplace"))
            browserOpener(url, opening.browser)
            return
        }
    }
}

/// True for Zoom personal-room links (e.g. `https://zoom.us/my/username` or
/// `https://company.zoom.us/my/username`). Personal rooms cannot be launched
/// through the `zoommtg://` deep link, so they must open in the browser.
func isZoomPersonalRoomURL(_ url: URL) -> Bool {
    guard let host = url.host, host.contains("zoom") else { return false }
    return url.path.contains("/my/")
}

enum ZoomWebOpenDestination: Equatable {
    case selectedBrowser
    case systemBrowser
    case zoomApp(URL)
    case defaultBrowser
}

func zoomWebOpenDestination(for url: URL, browser: Browser) -> ZoomWebOpenDestination {
    guard browser == zoomAppBrowser else { return .selectedBrowser }
    guard !isZoomPersonalRoomURL(url) else { return .systemBrowser }

    let urlString = url.absoluteString
        .replacingOccurrences(of: "?", with: "&")
        .replacingOccurrences(of: "/j/", with: "/join?confno=")
    guard let rewritten = URL(string: urlString),
          var appComponents = URLComponents(url: rewritten, resolvingAgainstBaseURL: false)
    else {
        return .defaultBrowser
    }
    appComponents.scheme = "zoommtg"
    guard let appURL = appComponents.url else { return .defaultBrowser }
    return .zoomApp(appURL)
}

enum ZoomWebAppURLPolicy {
    static func webAppURL(for url: URL) -> URL? {
        guard !isZoomPersonalRoomURL(url),
              let host = url.host?.lowercased(),
              isSupportedZoomHost(host),
              url.pathComponents.count == 3,
              url.pathComponents[1] == "j"
        else { return nil }

        let meetingID = url.pathComponents[2]
        guard meetingID.count >= 6,
              meetingID.allSatisfy(\.isNumber)
        else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "app.zoom.us"
        components.path = "/wc/\(meetingID)/start"
        components.queryItems = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems
        return components.url
    }

    private static func isSupportedZoomHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".").map(String.init)
        for (index, label) in labels.enumerated() {
            let suffix = labels.dropFirst(index + 1).joined(separator: ".")
            if label == "zoom" || label == "zoom-x",
               ["us", "com", "com.cn", "de"].contains(suffix) {
                return true
            }
            if label == "zoomgov", suffix == "com" {
                return true
            }
        }
        return false
    }
}

/// Converts the https Zoom URL to a `zoommtg://` app URL, falling back to browser.
/// Personal room links (`/my/`) open in the browser and never go through the app.
struct ZoomWebOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser _: Browser
    ) {
        if opening.mode == .zoomWebApp {
            if let webAppURL = ZoomWebAppURLPolicy.webAppURL(for: url) {
                webAppURL.openIn(browser: opening.browser)
            } else {
                url.openIn(browser: opening.browser)
            }
            return
        }

        let legacyBrowser = opening.mode == .zoomApp ? zoomAppBrowser : opening.browser
        switch zoomWebOpenDestination(for: url, browser: legacyBrowser) {
        case .selectedBrowser:
            url.openIn(browser: opening.browser)
        case .systemBrowser:
            url.openIn(browser: systemDefaultBrowser)
        case .zoomApp(let appURL):
            let result = appURL.openInDefaultBrowser()
            if !result {
                AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Zoom"))
                url.openInDefaultBrowser()
            }
        case .defaultBrowser:
            url.openInDefaultBrowser()
        }
    }
}

/// Converts the https Teams URL to an `msteams://` app URL, falling back to browser.
struct TeamsOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser _: Browser
    ) {
        if opening.mode == .teamsApp {
            guard var appComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                url.openInDefaultBrowser()
                return
            }
            appComponents.scheme = "msteams"
            let result = appComponents.url?.openInDefaultBrowser() ?? false
            if !result {
                AppMessageCenter.shared.post(
                    .meetingAppUnavailable(name: "Microsoft Teams")
                )
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: opening.browser)
        }
    }
}

/// Opens Jitsi via `jitsi-meet://` app scheme, falling back to browser.
struct JitsiOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(
        url: URL,
        opening: ResolvedMeetingOpening,
        defaultBrowser _: Browser
    ) {
        if opening.mode == .jitsiApp {
            guard var appComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                url.openInDefaultBrowser()
                return
            }
            appComponents.scheme = "jitsi-meet"
            let result = appComponents.url?.openInDefaultBrowser() ?? false
            if !result {
                AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Jitsi"))
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: opening.browser)
        }
    }
}

// MARK: - Strategy lookup

/// Returns the open strategy for the given service (or the default browser
/// strategy when the service is `nil` or has no custom strategy).
func openStrategy(for service: MeetingServices?) -> any MeetingOpenStrategy {
    guard let service else {
        return DefaultBrowserOpenStrategy()
    }
    return strategiesByService[service] ?? DefaultBrowserOpenStrategy()
}

private let strategiesByService: [MeetingServices: any MeetingOpenStrategy] = [
    // Google Meet
    .meet: GoogleMeetOpenStrategy(),
    .meetStream: GoogleMeetOpenStrategy(),

    // Zoom web URL → app scheme
    .zoom: ZoomWebOpenStrategy(),
    .zoomgov: ZoomWebOpenStrategy(),

    // Zoom native app scheme → browser fallback
    .zoom_native: ZoomNativeOpenStrategy(),

    // Microsoft Teams
    .teams: TeamsOpenStrategy(),

    // Workplace
    .facebook_workspace: WorkplaceOpenStrategy(),

    // Jitsi
    .jitsi: JitsiOpenStrategy(),

    // Slack huddle
    .slack: SlackHuddleOpenStrategy(),

    // Riverside
    .riverside: RiversideOpenStrategy(),

    // FaceTime
    .facetime: NativeSchemeOpenStrategy(schemePrefix: "facetime://"),
    .facetimeaudio: NativeSchemeOpenStrategy(schemePrefix: "facetime-audio://"),

    // Phone
    .phone: NativeSchemeOpenStrategy(schemePrefix: "tel://")
]
