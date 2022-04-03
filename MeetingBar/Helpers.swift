//
//  Helpers.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import AppKit
import Cocoa
import Defaults
import EventKit

struct MeetingLink: Equatable {
    let service: MeetingServices?
    var url: URL
}

struct Bookmark: Encodable, Decodable, Hashable {
    var name: String
    var service: MeetingServices
    var url: String
}

/**
 * this method will extract m365 safe links if any of these links are found in the given text..
 * The method will extract the real url from safe links and decode it, so that the following regex logic can detect the meeting service.
 *
 * The original link looks like this
 *https://nam12.safelinks.protection.outlook.com/ap/t-59584e83/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_[obfuscated]&data=[obfuscated]
 *
 * and the method will extract it to https://teams.microsoft.com/l/meetup-join/19%3ameeting_[obfuscated]
 * If no m365 links are found, the original text is returned.
 *
 */
private func cleanupOutlookSafeLinks(rawText: String) -> String {
    var text = rawText
    var links = UtilsRegex.outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    if !links.isEmpty {
        repeat {
            let urlRange = links[0].range(at: 1)
            let safeLinks = links.map { String(text[Range($0.range, in: text)!]) }
            if !safeLinks.isEmpty {
                let serviceUrl = (text as NSString).substring(with: urlRange)
                text = text.replacingOccurrences(of: safeLinks[0], with: serviceUrl.decodeUrl()!)
            }
            links = UtilsRegex.outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        } while !links.isEmpty
    }
    return text
}

func getMatch(text: String, regex: NSRegularExpression) -> String? {
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range, in: text)!]) }

    if !resultsMap.isEmpty {
        let match = resultsMap[0]
        return match
    }
    return nil
}

func hasMatch(text: String, regex: NSRegularExpression) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

func cleanUpNotes(_ notes: String) -> String {
    let zoomSeparator = "\n──────────"
    let meetSeparator = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
    let cleanNotes = notes
        .components(separatedBy: zoomSeparator)[0]
        .components(separatedBy: meetSeparator)[0]
        .htmlTagsStripped()
    return cleanNotes
}

func getRegexForService(_ service: MeetingServices) -> NSRegularExpression? {
    let regexes = LinksRegex()
    let mirror = Mirror(reflecting: regexes)

    for child in mirror.children {
        if child.label == String(describing: service) {
            return child.value as? NSRegularExpression
        }
    }
    return nil
}

func getEmailAccount(_ source: String?) -> String? {
    // Hacky and likely to break, but should work until Apple changes something
    let regex = UtilsRegex.emailAddress
    if let text = source {
        let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let resultsMap = resultsIterator.map { String(text[Range($0.range(at: 1), in: text)!]) }
        if !resultsMap.isEmpty {
            return resultsMap.first
        }
    }
    return nil
}

func detectLink(_ rawText: String) -> MeetingLink? {
    let text = cleanupOutlookSafeLinks(rawText: rawText)

    for pattern in Defaults[.customRegexes] {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            if let link = getMatch(text: text, regex: regex) {
                if let url = URL(string: link) {
                    return MeetingLink(service: MeetingServices.other, url: url)
                }
            }
        }
    }

    for service in MeetingServices.allCases {
        if let regex = getRegexForService(service) {
            if let link = getMatch(text: text, regex: regex) {
                if let url = URL(string: link) {
                    return MeetingLink(service: service, url: url)
                }
            }
        }
    }
    return nil
}

func openEvent(_ event: MBEvent) {
    let eventTitle = event.title
    if let meetingLink = event.meetingLink {
        if Defaults[.runJoinEventScript], Defaults[.joinEventScriptLocation] != nil {
            if let url = Defaults[.joinEventScriptLocation]?.appendingPathComponent("joinEventScript.scpt") {
                let task = try! NSUserAppleScriptTask(url: url)
                task.execute { error in
                    if let error = error {
                        sendNotification("status_bar_error_apple_script_title".loco(), error.localizedDescription)
                    }
                }
            }
        }
        openMeetingURL(meetingLink.service, meetingLink.url, nil)
    } else if let eventUrl = event.url {
        eventUrl.openInDefaultBrowser()
    } else {
        sendNotification("status_bar_error_link_missed_title".loco(eventTitle), "status_bar_error_link_missed_message".loco())
    }
}

func openMeetingURL(_ service: MeetingServices?, _ url: URL, _ browser: Browser?) {
    switch service {
    case .jitsi:
        if Defaults[.useAppForJitsiLinks] {
            var jitsiAppUrl = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            jitsiAppUrl.scheme = "jitsi-meet"
            let result = jitsiAppUrl.url!.openInDefaultBrowser()
            if !result {
                sendNotification("status_bar_error_jitsi_link_title".loco(), "status_bar_error_jitsi_link_message".loco())
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: browser ?? systemDefaultBrowser)
        }
    case .meet:
        let browser = browser ?? Defaults[.meetBrowser]
        if browser == MeetInOneBrowser {
            let meetInOneUrl = URL(string: "meetinone://url=" + url.absoluteString)!
            meetInOneUrl.openInDefaultBrowser()
        } else {
            url.openIn(browser: browser)
        }

    case .teams:
        if Defaults[.useAppForTeamsLinks] {
            var teamsAppURL = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            teamsAppURL.scheme = "msteams"
            let result = teamsAppURL.url!.openInDefaultBrowser()
            if !result {
                sendNotification("status_bar_error_teams_link_title".loco(), "status_bar_error_teams_link_message".loco())
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: browser ?? systemDefaultBrowser)
        }

    case .zoom, .zoomgov:
        if Defaults[.useAppForZoomLinks] {
            if url.absoluteString.contains("/my/") {
                url.openIn(browser: browser ?? systemDefaultBrowser)
            }
            let urlString = url.absoluteString.replacingOccurrences(of: "?", with: "&").replacingOccurrences(of: "/j/", with: "/join?confno=")
            var zoomAppUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomAppUrl.scheme = "zoommtg"
            let result = zoomAppUrl.url!.openInDefaultBrowser()
            if !result {
                sendNotification("status_bar_error_zoom_app_link_title".loco(), "status_bar_error_zoom_app_link_message".loco())
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: browser ?? systemDefaultBrowser)
        }
    case .zoom_native:
        let result = url.openInDefaultBrowser()
        if !result {
            sendNotification("status_bar_error_zoom_native_link_title".loco(), "status_bar_error_zoom_native_link_message".loco())

            let urlString = url.absoluteString.replacingFirstOccurrence(of: "&", with: "?").replacingOccurrences(of: "/join?confno=", with: "/j/")
            var zoomBrowserUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomBrowserUrl.scheme = "https"
            zoomBrowserUrl.url!.openInDefaultBrowser()
        }
    case .facetime:
        NSWorkspace.shared.open(URL(string: "facetime://" + url.absoluteString)!)
    case .facetimeaudio:
        NSWorkspace.shared.open(URL(string: "facetime-audio://" + url.absoluteString)!)
    case .phone:
        NSWorkspace.shared.open(URL(string: "tel://" + url.absoluteString)!)

    default:
        url.openIn(browser: browser ?? systemDefaultBrowser)
    }
}

func compareVersions(_ version_x: String, _ version_y: String) -> Bool {
    version_x.compare(version_y, options: .numeric) == .orderedDescending
}

func bundleIdentifier(forAppName appName: String) -> String? {
    let workspace = NSWorkspace.shared
    let appPath = workspace.fullPath(forApplication: appName)
    if let appPath = appPath {
        let appBundle = Bundle(path: appPath)
        return appBundle?.bundleIdentifier
    }
    return nil
}

/**
 * adds the default browsers for the browser dialog
 */
func addInstalledBrowser() {
    let existingBrowsers = Defaults[.browsers]

    var appUrls = LSCopyApplicationURLsForURL(URL(string: "https:")! as CFURL, .all)?.takeRetainedValue() as? [URL]

    if !appUrls!.isEmpty {
        appUrls = appUrls?.sorted { $0.path.fileName() < $1.path.fileName() }
        appUrls?.forEach {
            let browser = Browser(name: $0.path.fileName(), path: $0.path)
            if !existingBrowsers.contains(where: { $0.name == browser.path.fileName() }) {
                Defaults[.browsers].append(browser)
            }
        }
    }
}

func emailEventAttendees(_ event: MBEvent) {
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

func hexStringToUIColor(hex: String) -> NSColor {
    var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    if cString.hasPrefix("#") {
        cString.remove(at: cString.startIndex)
    }

    if (cString.count) != 6 {
        return NSColor.gray
    }

    var rgbValue: UInt64 = 0
    Scanner(string: cString).scanHexInt64(&rgbValue)

    return NSColor(
        red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
        alpha: CGFloat(1.0)
    )
}

func getNextEvent(events: [MBEvent]) -> MBEvent? {
    var nextEvent: MBEvent?

    let now = Date()
    let startPeriod = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
    var endPeriod: Date

    let todayMidnight = Calendar.current.startOfDay(for: now)
    switch Defaults[.showEventsForPeriod] {
    case .today:
        endPeriod = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!
    case .today_n_tomorrow:
        endPeriod = Calendar.current.date(byAdding: .day, value: 2, to: todayMidnight)!
    }

    var nextEvents = events.filter { $0.endDate > startPeriod && $0.startDate < endPeriod }

    // Filter out personal events, if not marked as 'active'
    if Defaults[.personalEventsAppereance] != .show_active {
        nextEvents = nextEvents.filter { $0.attendees.count > 0 }
    }

    // If the current event is still going on,
    // but the next event is closer than 13 minutes later
    // then show the next event
    for event in nextEvents {
        if event.isAllDay {
            continue
        } else {
            if Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.show_inactive_without_meeting_link {
                if event.meetingLink == nil {
                    continue
                }
            } else if Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.hide_without_meeting_link {
                if event.meetingLink?.url == nil {
                    continue
                }
            }
        }

        if event.participationStatus == .declined { // Skip event if declined
            continue
        }

        if event.participationStatus == .pending, Defaults[.showPendingEvents] == PendingEventsAppereance.hide || Defaults[.showPendingEvents] == PendingEventsAppereance.show_inactive {
            continue
        }

        if event.status == .canceled {
            continue
        } else {
            if nextEvent == nil {
                nextEvent = event
                continue
            } else {
                let soon = now.addingTimeInterval(780) // 13 min from now
                if event.startDate < soon {
                    nextEvent = event
                } else {
                    break
                }
            }
        }
    }
    return nextEvent
}

func checkIsFantasticalInstalled() -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.flexibits.fantastical2.mac") != nil
}

func getClipboardContent() -> String {
    let pasteboard = NSPasteboard.general
    return pasteboard.string(forType: .string) ?? ""
}

func getIconForMeetingService(_ meetingService: MeetingServices?) -> NSImage {
    var image = NSImage(named: "no_online_session")!
    image.size = NSSize(width: 16, height: 16)

    switch meetingService {
    // tested and verified
    case .some(.teams):
        image = NSImage(named: "ms_teams_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.meet), .some(.meetStream):
        image = NSImage(named: "google_meet_icon")!
        image.size = NSSize(width: 16, height: 13.2)

    // tested and verified -> deprecated, can be removed because hangouts was replaced by google meet
    case .some(.hangouts):
        image = NSImage(named: "google_hangouts_icon")!
        image.size = NSSize(width: 16, height: 17.8)

    // tested and verified
    case .some(.zoom), .some(.zoomgov), .some(.zoom_native):
        image = NSImage(named: "zoom_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.webex):
        image = NSImage(named: "webex_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.jitsi):
        image = NSImage(named: "jitsi_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.chime):
        image = NSImage(named: "amazon_chime_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.ringcentral):
        image = NSImage(named: "ringcentral_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.gotomeeting):
        image = NSImage(named: "gotomeeting_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.gotowebinar):
        image = NSImage(named: "gotowebinar_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.bluejeans):
        image = NSImage(named: "bluejeans_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.eight_x_eight):
        image = NSImage(named: "8x8_icon")!
        image.size = NSSize(width: 16, height: 8)

    // tested and verified
    case .some(.demio):
        image = NSImage(named: "demio_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.join_me):
        image = NSImage(named: "joinme_icon")!
        image.size = NSSize(width: 16, height: 10)

    // tested and verified
    case .some(.whereby):
        image = NSImage(named: "whereby_icon")!
        image.size = NSSize(width: 16, height: 18)

    // tested and verified
    case .some(.uberconference):
        image = NSImage(named: "uberconference_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.blizz), .some(.teamviewer_meeting):
        image = NSImage(named: "teamviewer_meeting_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.vsee):
        image = NSImage(named: "vsee_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.starleaf):
        image = NSImage(named: "starleaf_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.duo):
        image = NSImage(named: "google_duo_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.voov):
        image = NSImage(named: "voov_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.skype):
        image = NSImage(named: "skype_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.skype4biz), .some(.skype4biz_selfhosted):
        image = NSImage(named: "skype_business_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.lifesize):
        image = NSImage(named: "lifesize_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.facebook_workspace):
        image = NSImage(named: "facebook_workplace_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.youtube):
        image = NSImage(named: "youtube_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.coscreen):
        image = NSImage(named: "coscreen_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.vowel):
        image = NSImage(named: "vowel_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.zhumu):
        image = NSImage(named: "zhumu_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.lark):
        image = NSImage(named: "lark_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.feishu):
        image = NSImage(named: "feishu_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.vimeo_showcases):
        image = NSImage(named: "vimeo_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.ovice):
        image = NSImage(named: "ovice_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.facetime):
        image = NSImage(named: "facetime_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.pop):
        image = NSImage(named: "pop_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.chorus):
        image = NSImage(named: "chorus_icon")!
        image!.size = NSSize(width: 16, height: 16)

    case .some(.livestorm):
        image = NSImage(named: "livestorm_icon")!
        image!.size = NSSize(width: 16, height: 16)

    case .some(.gong):
        image = NSImage(named: "gong_icon")!
        image!.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .none:
        image = NSImage(named: "no_online_session")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.vonageMeetings):
        image = NSImage(named: "vonage_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.url):
        image = NSImage(named: NSImage.touchBarOpenInBrowserTemplateName)!
        image.size = NSSize(width: 16, height: 16)

    default:
        break
    }

    return image
}
