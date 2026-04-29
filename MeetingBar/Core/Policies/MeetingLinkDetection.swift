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

let meetingLinkRegexPatterns: [MeetingServices: String] = [
    .meet: #"https?://meet.google.com/(_meet/)?[a-z-]+"#,
    .zoom: #"https:\/\/(?:[a-zA-Z0-9-.]+)?zoom(-x)?\.(?:us|com|com\.cn|de)\/(?:my|[a-z]{1,2}|webinar)\/[-a-zA-Z0-9()@:%_\+.~#?&=\/]*"#,
    .zoom_native: #"zoommtg://([a-z0-9-.]+)?zoom(-x)?\.(?:us|com|com\.cn|de)/join[-a-zA-Z0-9()@:%_\+.~#?&=\/]*"#,
    .teams: #"https?://(gov.)?teams\.microsoft\.(com|us)/l/meetup-join/[a-zA-Z0-9_%\/=\-\+\.?]+"#,
    .webex: #"https?://(?:[A-Za-z0-9-]+\.)?webex\.com(?:(?:/[-A-Za-z0-9]+/j\.php\?MTID=[A-Za-z0-9]+(?:&\S*)?)|(?:/(?:meet|join)/[A-Za-z0-9\-._@]+(?:\?\S*)?))"#,
    .chime: #"https?://([a-z0-9-.]+)?chime\.aws/[0-9]*"#,
    .jitsi: #"https?://meet\.jit\.si/[^\s]*"#,
    .ringcentral: #"https?://([a-z0-9.]+)?ringcentral\.com/[^\s]*"#,
    .gotomeeting: #"https?://([a-z0-9.]+)?gotomeeting\.com/[^\s]*"#,
    .gotowebinar: #"https?://([a-z0-9.]+)?gotowebinar\.com/[^\s]*"#,
    .bluejeans: #"https?://([a-z0-9.]+)?bluejeans\.com/[^\s]*"#,
    .eight_x_eight: #"https?://8x8\.vc/[^\s]*"#,
    .demio: #"https?://event\.demio\.com/[^\s]*"#,
    .join_me: #"https?://join\.me/[^\s]*"#,
    .whereby: #"https?://whereby\.com/[^\s]*"#,
    .uberconference: #"https?://uberconference\.com/[^\s]*"#,
    .blizz: #"https?://go\.blizz\.com/[^\s]*"#,
    .teamviewer_meeting: #"https?://go\.teamviewer\.com/[^\s]*"#,
    .vsee: #"https?://vsee\.com/[^\s]*"#,
    .starleaf: #"https?://meet\.starleaf\.com/[^\s]*"#,
    .duo: #"https?://duo\.app\.goo\.gl/[^\s]*"#,
    .voov: #"https?://voovmeeting\.com/[^\s]*"#,
    .facebook_workspace: #"https?://([a-z0-9-.]+)?workplace\.com/groupcall/[^\s]+"#,
    .skype: #"https?://join\.skype\.com/[^\s]*"#,
    .lifesize: #"https?://call\.lifesizecloud\.com/[^\s]*"#,
    .youtube: #"https?://((www|m)\.)?(youtube\.com|youtu\.be)/[^\s]*"#,
    .vonageMeetings: #"https?://meetings\.vonage\.com/[0-9]{9}"#,
    .meetStream: #"https?://stream\.meet\.google\.com/stream/[a-z0-9-]+"#,
    .around: #"https?://(meet\.)?around\.co/[^\s]*"#,
    .jam: #"https?://jam\.systems/[^\s]*"#,
    .discord: #"(http|https|discord)://(www\.)?(canary\.)?discord(app)?\.([a-zA-Z]{2,})(.+)?"#,
    .blackboard_collab: #"https?://us\.bbcollab\.com/[^\s]*"#,
    .coscreen: #"https?://join\.coscreen\.co/[^\s]*"#,
    .vowel: #"https?://([a-z0-9.]+)?vowel\.com/#/g/[^\s]*"#,
    .zhumu: #"https://welink\.zhumu\.com/j/[0-9]+?pwd=[a-zA-Z0-9]+"#,
    .lark: #"https://vc\.larksuite\.com/j/[0-9]+"#,
    .feishu: #"https://vc\.feishu\.cn/j/[0-9]+"#,
    .vimeo: #"https://vimeo\.com/(showcase|event)/[0-9]+|https://venues\.vimeo\.com/[^\s]+"#,
    .ovice: #"https://([a-z0-9-.]+)?ovice\.(in|com)/[^\s]*"#,
    .facetime: #"https://facetime\.apple\.com/join[^\s]*"#,
    .chorus: #"https?://go\.chorus\.ai/[^\s]+"#,
    .pop: #"https?://pop\.com/j/[0-9-]+"#,
    .gong: #"https?://([a-z0-9-.]+)?join\.gong\.io/[^\s]+"#,
    .livestorm: #"https?://app\.livestorm\.com/p/[^\s]+"#,
    .luma: #"https://lu\.ma/join/[^\s]*"#,
    .preply: #"https://preply\.com/[^\s]*"#,
    .userzoom: #"https://go\.userzoom\.com/participate/[a-z0-9-]+"#,
    .venue: #"https://app\.venue\.live/app/[^\s]*"#,
    .teemyco: #"https://app\.teemyco\.com/room/[^\s]*"#,
    .demodesk: #"https://demodesk\.com/[^\s]*"#,
    .zoho_cliq: #"https://cliq\.zoho\.eu/meetings/[^\s]*"#,
    .zoomgov: #"https?://([a-z0-9.]+)?zoomgov\.com/j/[a-zA-Z0-9?&=]+"#,
    .skype4biz: #"https?://meet\.lync\.com/[^\s]*"#,
    .skype4biz_selfhosted: #"https?:\/\/(meet|join)\.[^\s]*\/[a-z0-9.]+/meet\/[A-Za-z0-9./]+"#,
    .hangouts: #"https?://hangouts\.google\.com/[^\s]*"#,
    .slack: #"https?://app\.slack\.com/huddle/[A-Za-z0-9./]+"#,
    .reclaim: #"https?://reclaim\.ai/z/[A-Za-z0-9./]+"#,
    .tuple: #"https://tuple\.app/c/[^\s]*"#,
    .gather: #"https?://app.gather.town/app/[A-Za-z0-9]+/[A-Za-z0-9_%\-]+\?(spawnToken|meeting)=[^\s]*"#,
    .pumble: #"https?://meet\.pumble\.com/[a-z-]+"#,
    .suitConference: #"https?://([a-z0-9.]+)?conference\.istesuit\.com/[^\s]*+"#,
    .doxyMe: #"https://([a-z0-9.]+)?doxy\.me/[^\s]*"#,
    .calcom: #"https?://app.cal\.com/video/[A-Za-z0-9./]+"#,
    .zmPage: #"https?://([a-zA-Z0-9.]+)\.zm\.page"#,
    .livekit: #"https?://meet[a-zA-Z0-9.]*\.livekit\.io/rooms/[a-zA-Z0-9-#]+"#,
    .meetecho: #"https?://meetings\.conf\.meetecho\.com/.+"#,
    .streamyard: #"https://(?:www\.)?streamyard\.com/(?:guest/)?([a-z0-9]{8,13})(?:/|\?[^ \n]*)?"#,
    .riverside: #"https?://riverside\.(com|fm)/studio/[^\s]*"#
]

private let meetingLinkRegexes: [MeetingServices: NSRegularExpression] = meetingLinkRegexPatterns.compactMapValues { pattern in
    do {
        return try NSRegularExpression(pattern: pattern)
    } catch {
        NSLog("Ignoring invalid built-in meeting link regex '\(pattern)': \(error)")
        return nil
    }
}

private let outlookSafeLinkRegex = try? NSRegularExpression(pattern: #"https://[\S]+\.safelinks\.protection\.outlook\.com/[\S]+url=([\S]*)"#)

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
        var links = outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
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
                links = outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
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

private extension String {
    var containsHTMLTags: Bool {
        range(of: #"</?[A-z][ \t\S]*>"#, options: .regularExpression) != nil
    }
}
