//
//  MeetingOpenStrategy.swift
//  MeetingBar
//
//  Per-provider opening strategies extracted from the openMeetingURL switch.
//  Each strategy encapsulates the full open logic for a class of providers
//  so callers don't need to match on MeetingServices.
//
//  Phase 3 PR 4: openMeetingURL delegates to these strategies.
//  Phase 6: strategies gain injected side-effect services instead of calling
//  NSWorkspace / sendNotification directly.
//

import AppKit
import Defaults

// MARK: - Strategy protocol

/// Encapsulates how a meeting provider URL should be opened.
protocol MeetingOpenStrategy: Sendable {
    func open(url: URL, browser: Browser?)
}

// MARK: - Default browser

/// Opens the URL in the app-wide default browser (or the explicitly passed browser).
struct DefaultBrowserOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        url.openIn(browser: browser ?? Defaults[.defaultBrowser])
    }
}

// MARK: - Native-scheme (no fallback to browser)

/// Opens via a native-only URL scheme (e.g. `facetime://`, `tel://`).
struct NativeSchemeOpenStrategy: MeetingOpenStrategy, Sendable {
    let schemePrefix: String

    func open(url: URL, browser _: Browser?) {
        guard let nativeURL = URL(string: schemePrefix + url.absoluteString) else { return }
        NSWorkspace.shared.open(nativeURL)
    }
}

// MARK: - Zoom native (app→browser fallback)

/// Handles `zoommtg://` links: tries the app, falls back to an https URL if
/// the app is missing.
struct ZoomNativeOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser _: Browser?) {
        let result = url.openInDefaultBrowser()
        if !result {
            sendNotification(
                "status_bar_error_app_link_title".loco("Zoom"),
                "status_bar_error_app_link_message".loco("Zoom")
            )
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

// MARK: - MeetInOne

/// Opens Google Meet links in the MeetInOne app when configured.
struct MeetInOneOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.meet.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == meetInOneBrowser {
            let meetInOneURL = URL(string: "meetinone://url=" + url.absoluteString)!
            meetInOneURL.openInDefaultBrowser()
        } else {
            url.openIn(browser: resolved)
        }
    }
}

// MARK: - Slack huddle

/// Extracts the Slack team/huddle IDs from the https URL and opens the
/// native `slack://join-huddle` deep link, falling back to browser.
struct SlackHuddleOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.slack.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == slackAppBrowser {
            let components = url.pathComponents
            guard components.count >= 4 else {
                url.openIn(browser: Defaults[.defaultBrowser])
                return
            }
            let teamID = components[2]
            let huddleID = components[3]
            let slackURL = URL(string: "slack://join-huddle?team=\(teamID)&id=\(huddleID)")!
            let result = slackURL.openInDefaultBrowser()
            if !result {
                sendNotification(
                    "status_bar_error_app_link_title".loco("Slack"),
                    "status_bar_error_app_link_message".loco("Slack")
                )
                url.openIn(browser: Defaults[.defaultBrowser])
            }
        } else {
            url.openIn(browser: resolved)
        }
    }
}

// MARK: - Riverside (dual-scheme fallback)

/// Tries `riversidefm://` then `riverside.fm://` before falling back to browser.
struct RiversideOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.riverside.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == riversideAppBrowser {
            for scheme in ["riversidefm", "riverside.fm"] {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.scheme = scheme
                if let appURL = components.url, appURL.openInDefaultBrowser() { return }
            }
            sendNotification(
                "status_bar_error_app_link_title".loco("Riverside"),
                "status_bar_error_app_link_message".loco("Riverside")
            )
            url.openIn(browser: Defaults[.defaultBrowser])
        } else {
            url.openIn(browser: resolved)
        }
    }
}

// MARK: - Zoom web (app scheme)

/// Converts the https Zoom URL to a `zoommtg://` app URL, falling back to browser.
/// Personal room links (`/my/`) are always opened in the browser first.
struct ZoomWebOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.zoom.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == zoomAppBrowser {
            if url.absoluteString.contains("/my/") {
                url.openIn(browser: systemDefaultBrowser)
            }
            let urlString = url.absoluteString
                .replacingOccurrences(of: "?", with: "&")
                .replacingOccurrences(of: "/j/", with: "/join?confno=")
            var appComponents = URLComponents(
                url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            appComponents.scheme = "zoommtg"
            let result = appComponents.url!.openInDefaultBrowser()
            if !result {
                sendNotification(
                    "status_bar_error_app_link_title".loco("Zoom"),
                    "status_bar_error_app_link_message".loco("Zoom")
                )
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: resolved)
        }
    }
}

// MARK: - Teams app scheme

/// Converts the https Teams URL to an `msteams://` app URL, falling back to browser.
struct TeamsOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.teams.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == teamsAppBrowser {
            var appComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            appComponents.scheme = "msteams"
            let result = appComponents.url!.openInDefaultBrowser()
            if !result {
                sendNotification(
                    "status_bar_error_app_link_title".loco("Microsoft Teams"),
                    "status_bar_error_app_link_message".loco("Microsoft Teams")
                )
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: resolved)
        }
    }
}

// MARK: - Jitsi app scheme

/// Opens Jitsi via `jitsi-meet://` app scheme, falling back to browser.
struct JitsiOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.jitsi.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == jitsiAppBrowser {
            var appComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            appComponents.scheme = "jitsi-meet"
            let result = appComponents.url!.openInDefaultBrowser()
            if !result {
                sendNotification(
                    "status_bar_error_app_link_title".loco("Jitsi"),
                    "status_bar_error_app_link_message".loco("Jitsi")
                )
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: resolved)
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

private nonisolated(unsafe) let strategiesByService: [MeetingServices: any MeetingOpenStrategy] = [
    // Google Meet
    .meet: MeetInOneOpenStrategy(),
    .meetStream: MeetInOneOpenStrategy(),

    // Zoom web URL → app scheme
    .zoom: ZoomWebOpenStrategy(),
    .zoomgov: ZoomWebOpenStrategy(),

    // Zoom native app scheme → browser fallback
    .zoom_native: ZoomNativeOpenStrategy(),

    // Microsoft Teams
    .teams: TeamsOpenStrategy(),

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
