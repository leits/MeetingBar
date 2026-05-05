//
//  MeetingLinkDetection.swift
//  MeetingBar
//

import AppKit
import Foundation

enum MeetingServices: String, Codable, CaseIterable, Sendable {
    case phone = "Phone"
    case meet = "Google Meet"
    case hangouts = "Google Hangouts"
    case zoom = "Zoom"
    case zoom_native = "Zoom native"
    case teams = "Microsoft Teams"
    case webex = "Cisco Webex"
    case jitsi = "Jitsi"
    case chime = "Amazon Chime"
    case ringcentral = "Ring Central"
    case gotomeeting = "GoToMeeting"
    case gotowebinar = "GoToWebinar"
    case bluejeans = "BlueJeans"
    case eight_x_eight = "8x8"
    case demio = "Demio"
    case join_me = "Join.me"
    case zoomgov = "ZoomGov"
    case whereby = "Whereby"
    case uberconference = "Uber Conference"
    case blizz = "Blizz"
    case teamviewer_meeting = "Teamviewer Meeting"
    case vsee = "VSee"
    case starleaf = "StarLeaf"
    case duo = "Google Duo"
    case voov = "Tencent VooV"
    case facebook_workspace = "Facebook Workspace"
    case lifesize = "Lifesize"
    case skype = "Skype"
    case skype4biz = "Skype For Business"
    case skype4biz_selfhosted = "Skype For Business (SH)"
    case facetime = "Facetime"
    case pop = "Pop"
    case chorus = "Chorus"
    case gong = "Gong"
    case livestorm = "Livestorm"
    case facetimeaudio = "Facetime Audio"
    case youtube = "YouTube"
    case vonageMeetings = "Vonage Meetings"
    case meetStream = "Google Meet Stream"
    case around = "Around"
    case jam = "Jam"
    case discord = "Discord"
    case blackboard_collab = "Blackboard Collaborate"
    case url = "Any Link"
    case coscreen = "CoScreen"
    case vowel = "Vowel"
    case zhumu = "Zhumu"
    case lark = "Lark"
    case feishu = "Feishu"
    case vimeo = "Vimeo"
    case ovice = "oVice"
    case luma = "Luma"
    case preply = "Preply"
    case userzoom = "UserZoom"
    case venue = "Venue"
    case teemyco = "Teemyco"
    case demodesk = "Demodesk"
    case zoho_cliq = "Zoho Cliq"
    case slack = "Slack"
    case gather = "Gather"
    case reclaim = "Reclaim.ai"
    case tuple = "Tuple"
    case pumble = "Pumble"
    case suitConference = "Suit Conference"
    case doxyMe = "Doxy.me"
    case calcom = "Cal Video"
    case zmPage = "zm.page"
    case livekit = "LiveKit Meet"
    case meetecho = "Meetecho"
    case streamyard = "StreamYard"
    case riverside = "Riverside"
    case other = "Other"
}

public struct MeetingLink: Hashable, Equatable, Sendable {
    let service: MeetingServices?
    var url: URL
}

// All built-in regex patterns are owned by MeetingProviderRegistry.
// Deprecated: use MeetingProviderRegistry.regexPatterns directly.
// Kept for one release cycle so external callers (e.g. existing tests) continue to compile.
@available(*, deprecated, renamed: "MeetingProviderRegistry.regexPatterns")
let meetingLinkRegexPatterns: [MeetingServices: String] = MeetingProviderRegistry.regexPatterns

private let meetingLinkRegexes: [MeetingServices: NSRegularExpression] =
    MeetingProviderRegistry.regexPatterns.compactMapValues { pattern in
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            NSLog("Ignoring invalid built-in meeting link regex '\(pattern)': \(error)")
            return nil
        }
    }

private let outlookSafeLinkRegex = try? NSRegularExpression(
    pattern: #"https://[\S]+\.safelinks\.protection\.outlook\.com/[\S]+url=([\S]*)"#)

func regex(for service: MeetingServices) -> NSRegularExpression? {
    meetingLinkRegexes[service]
}

func detectMeetingLink(_ rawText: String, customRegexes: [String] = []) -> MeetingLink? {
    let text = cleanupOutlookSafeLinks(rawText: rawText)

    for pattern in customRegexes {
        if let regex = try? NSRegularExpression(pattern: pattern),
            let link = getMatch(text: text, regex: regex),
            let url = URL(string: link) {
            return MeetingLink(service: MeetingServices.other, url: url)
        }
    }

    if text.contains("://") {
        for (svc, regex) in meetingLinkRegexes {
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let range = Range(match.range, in: text),
                let url = URL(string: String(text[range])) {
                return MeetingLink(service: svc, url: url)
            }
        }
    }
    return nil
}

func cleanupOutlookSafeLinks(rawText: String) -> String {
    guard let outlookSafeLinkRegex else { return rawText }

    var text = rawText
    autoreleasepool {
        var links = outlookSafeLinkRegex.matches(
            in: text, range: NSRange(text.startIndex..., in: text))
        if !links.isEmpty {
            repeat {
                let urlRange = links[0].range(at: 1)
                let safeLinks = links.compactMap { match -> String? in
                    guard let range = Range(match.range, in: text) else { return nil }
                    return String(text[range])
                }
                if !safeLinks.isEmpty {
                    let serviceURL = (text as NSString).substring(with: urlRange)
                    if let decodedServiceURL = serviceURL.removingPercentEncoding {
                        text = text.replacingOccurrences(of: safeLinks[0], with: decodedServiceURL)
                    }
                }
                links = outlookSafeLinkRegex.matches(
                    in: text, range: NSRange(text.startIndex..., in: text))
            } while !links.isEmpty
        }
    }
    return text
}

func getMatch(text: String, regex: NSRegularExpression) -> String? {
    var match: String?

    autoreleasepool {
        let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let resultsMap = resultsIterator.compactMap { result -> String? in
            guard let range = Range(result.range, in: text) else { return nil }
            return String(text[range])
        }

        if !resultsMap.isEmpty {
            match = resultsMap[0]
        }
    }

    return match
}

func htmlTagsStrippedForMeetingLinks(_ text: String) -> String {
    if !text.containsHTMLTags {
        return text
    }

    return autoreleasepool {
        guard let dataUTF16 = text.data(using: .utf16) else {
            return text
        }

        let attributedString = NSAttributedString(
            html: dataUTF16,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        )
        return attributedString?.string ?? text
    }
}

extension String {
    fileprivate var containsHTMLTags: Bool {
        range(of: #"</?[A-z][ \t\S]*>"#, options: .regularExpression) != nil
    }
}
