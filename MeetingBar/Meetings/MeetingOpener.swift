//
//  MeetingOpener.swift
//  MeetingBar
//

import AppKit
import Defaults

protocol MeetingOpeningPerforming {
    func runJoinEventScriptIfConfigured()
    func openMeetingLink(_ service: MeetingServices?, _ url: URL)
    func openEventURL(_ url: URL)
    func notifyMissingLink(title: String)
}

struct SystemMeetingOpeningPerformer: MeetingOpeningPerforming {
    func runJoinEventScriptIfConfigured() {
        guard Defaults[.runJoinEventScript],
              let scriptLocation = Defaults[.joinEventScriptLocation]
        else { return }
        let scriptURL = scriptLocation.appendingPathComponent("joinEventScript.scpt")
        let task = try? NSUserAppleScriptTask(url: scriptURL)
        task?.execute { error in
            if let error {
                AppMessageCenter.shared.post(
                    .joinScriptFailed(description: error.localizedDescription)
                )
            }
        }
    }

    func openMeetingLink(_ service: MeetingServices?, _ url: URL) {
        openMeetingURL(service, url, nil)
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
        performer: any MeetingOpeningPerforming = SystemMeetingOpeningPerformer()
    ) {
        let action = MeetingOpeningPolicy.action(
            for: MeetingOpeningEvent(
                title: event.title,
                meetingLink: event.meetingLink,
                eventURL: event.url
            ),
            runJoinEventScript: Defaults[.runJoinEventScript]
        )

        perform(action, performer: performer)
    }

    static func open(
        meetingLink: MeetingLink,
        performer: any MeetingOpeningPerforming = SystemMeetingOpeningPerformer()
    ) {
        perform(
            .openMeetingLink(meetingLink, runJoinScript: Defaults[.runJoinEventScript]),
            performer: performer
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

    static func perform(_ action: MeetingOpeningAction, performer: any MeetingOpeningPerforming) {
        switch action {
        case let .openMeetingLink(meetingLink, runJoinScript):
            if runJoinScript {
                performer.runJoinEventScriptIfConfigured()
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
protocol MeetingOpenStrategy: Sendable {
    func open(url: URL, browser: Browser?)
}

/// Opens the URL in the app-wide default browser (or the explicitly passed browser).
struct DefaultBrowserOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        url.openIn(browser: browser ?? Defaults[.defaultBrowser])
    }
}

/// Opens via a native-only URL scheme (e.g. `facetime://`, `tel://`).
struct NativeSchemeOpenStrategy: MeetingOpenStrategy, Sendable {
    let schemePrefix: String

    func open(url: URL, browser _: Browser?) {
        guard let nativeURL = URL(string: schemePrefix + url.absoluteString) else { return }
        NSWorkspace.shared.open(nativeURL)
    }
}

/// Handles `zoommtg://` links: tries the app, falls back to an https URL if
/// the app is missing.
struct ZoomNativeOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser _: Browser?) {
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
            guard let slackURL = URL(string: "slack://join-huddle?team=\(teamID)&id=\(huddleID)")
            else {
                url.openIn(browser: Defaults[.defaultBrowser])
                return
            }
            let result = slackURL.openInDefaultBrowser()
            if !result {
                AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Slack"))
                url.openIn(browser: Defaults[.defaultBrowser])
            }
        } else {
            url.openIn(browser: resolved)
        }
    }
}

/// Tries `riversidefm://` then `riverside.fm://` before falling back to browser.
struct RiversideOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.riverside.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == riversideAppBrowser {
            for scheme in ["riversidefm", "riverside.fm"] {
                guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                else { continue }
                components.scheme = scheme
                if let appURL = components.url, appURL.openInDefaultBrowser() { return }
            }
            AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Riverside"))
            url.openIn(browser: Defaults[.defaultBrowser])
        } else {
            url.openIn(browser: resolved)
        }
    }
}

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
            guard let rewritten = URL(string: urlString),
                var appComponents = URLComponents(url: rewritten, resolvingAgainstBaseURL: false)
            else {
                url.openInDefaultBrowser()
                return
            }
            appComponents.scheme = "zoommtg"
            let result = appComponents.url?.openInDefaultBrowser() ?? false
            if !result {
                AppMessageCenter.shared.post(.meetingAppUnavailable(name: "Zoom"))
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: resolved)
        }
    }
}

/// Converts the https Teams URL to an `msteams://` app URL, falling back to browser.
struct TeamsOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.teams.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == teamsAppBrowser {
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
            url.openIn(browser: resolved)
        }
    }
}

/// Opens Jitsi via `jitsi-meet://` app scheme, falling back to browser.
struct JitsiOpenStrategy: MeetingOpenStrategy, Sendable {
    func open(url: URL, browser: Browser?) {
        let resolved =
            browser ?? Defaults[.providerBrowsers][MeetingServices.jitsi.rawValue]
            ?? Defaults[.defaultBrowser]
        if resolved == jitsiAppBrowser {
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

private let strategiesByService: [MeetingServices: any MeetingOpenStrategy] = [
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
