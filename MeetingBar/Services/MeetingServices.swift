//
//  MeetingServices.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 09.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults
import Foundation

extension MeetingServices {
    var localizedValue: String {
        switch self {
        case .phone:
            return "constants_meeting_service_phone".loco()
        case .zoom_native:
            return "constants_meeting_service_zoom_native".loco()
        case .other:
            return "constants_meeting_service_other".loco()
        case .url:
            return "constants_meeting_service_url".loco()
        default:
            return rawValue
        }
    }
}

enum CreateMeetingLinks {
    static let meet = URL(string: "https://meet.google.com/new")!
    static let zoom = URL(string: "https://zoom.us/start?confno=123456789&zc=0")!
    static let teams = URL(string: "https://teams.microsoft.com/l/meeting/new?subject=")!
    static let jam = URL(string: "https://jam.systems/new")!
    static let coscreen = URL(string: "https://cs.new")!
    static let gcalendar = URL(string: "https://calendar.google.com/calendar/u/0/r/eventedit")!
    static let outlook_live = URL(string: "https://outlook.live.com/calendar/0/action/compose")!
    static let outlook_office365 = URL(string: "https://outlook.office365.com/calendar/0/action/compose")!
}

enum CreateMeetingServices: String, Defaults.Serializable, Codable, CaseIterable {
    case meet = "Google Meet"
    case zoom = "Zoom"
    case teams = "Microsoft Teams"
    case jam = "Jam"
    case coscreen = "CoScreen"
    case gcalendar = "Google Calendar"
    case outlook_live = "Outlook Live"
    case outlook_office365 = "Outlook Office365"
    case url = "Custom url"

    var localizedValue: String {
        switch self {
        case .url:
            return "constants_create_meeting_service_url".loco()
        default:
            return rawValue
        }
    }
}

func createMeeting() {
    let browser: Browser = Defaults[.browserForCreateMeeting]

    switch Defaults[.createMeetingService] {
    case .meet:
        openMeetingURL(MeetingServices.meet, CreateMeetingLinks.meet, browser)
    case .zoom:
        openMeetingURL(MeetingServices.zoom, CreateMeetingLinks.zoom, browser)
    case .teams:
        openMeetingURL(MeetingServices.teams, CreateMeetingLinks.teams, browser)
    case .jam:
        openMeetingURL(MeetingServices.jam, CreateMeetingLinks.jam, browser)
    case .coscreen:
        openMeetingURL(MeetingServices.coscreen, CreateMeetingLinks.coscreen, browser)
    case .gcalendar:
        openMeetingURL(nil, CreateMeetingLinks.gcalendar, browser)
    case .outlook_office365:
        openMeetingURL(nil, CreateMeetingLinks.outlook_office365, browser)
    case .outlook_live:
        openMeetingURL(nil, CreateMeetingLinks.outlook_live, browser)
    case .url:
        var url: String = Defaults[.createMeetingServiceUrl]
        let checkedUrl = NSURL(string: url)

        if !url.isEmpty, checkedUrl != nil {
            openMeetingURL(nil, URL(string: url)!, browser)
        } else {
            if !url.isEmpty {
                url += " "
            }

            sendNotification("create_meeting_error_title".loco(), "create_meeting_error_message".loco(url))
        }
    }
}

func openMeetingURL(_ service: MeetingServices?, _ url: URL, _ browser: Browser?) {
    switch service {
    case .meet:
        let browser = browser ?? Defaults[.meetBrowser]
        if browser == meetInOneBrowser {
            let meetInOneUrl = URL(string: "meetinone://url=" + url.absoluteString)!
            meetInOneUrl.openInDefaultBrowser()
        } else {
            url.openIn(browser: browser)
        }
    case .teams:
        let browser = browser ?? Defaults[.teamsBrowser]
        if browser == teamsAppBrowser {
            var teamsAppURL = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            teamsAppURL.scheme = "msteams"
            let result = teamsAppURL.url!.openInDefaultBrowser()
            if !result {
                sendNotification("status_bar_error_app_link_title".loco("Microsoft Teams"), "status_bar_error_app_link_message".loco("Microsoft Teams"))
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: browser)
        }
    case .zoom, .zoomgov:
        let browser = browser ?? Defaults[.zoomBrowser]
        if browser == zoomAppBrowser {
            if url.absoluteString.contains("/my/") {
                url.openIn(browser: systemDefaultBrowser)
            }
            let urlString = url.absoluteString.replacingOccurrences(of: "?", with: "&").replacingOccurrences(of: "/j/", with: "/join?confno=")
            var zoomAppUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomAppUrl.scheme = "zoommtg"
            let result = zoomAppUrl.url!.openInDefaultBrowser()
            if !result {
                sendNotification("status_bar_error_app_link_title".loco("Zoom"), "status_bar_error_app_link_message".loco("Zoom"))
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: browser)
        }
    case .zoom_native:
        let result = url.openInDefaultBrowser()
        if !result {
            sendNotification("status_bar_error_app_link_title".loco("Zoom"), "status_bar_error_app_link_message".loco("Zoom"))

            let urlString = url.absoluteString.replacingFirstOccurrence(of: "&", with: "?").replacingOccurrences(of: "/join?confno=", with: "/j/")
            var zoomBrowserUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomBrowserUrl.scheme = "https"
            zoomBrowserUrl.url!.openInDefaultBrowser()
        }
    case .jitsi:
        let browser = browser ?? Defaults[.jitsiBrowser]
        if browser == jitsiAppBrowser {
            var jitsiAppUrl = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            jitsiAppUrl.scheme = "jitsi-meet"
            let result = jitsiAppUrl.url!.openInDefaultBrowser()
            if !result {
                sendNotification("status_bar_error_app_link_title".loco("Jitsi"), "status_bar_error_app_link_message".loco("Jitis"))
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: browser)
        }
    case .slack:
        let browser = browser ?? Defaults[.slackBrowser]
        if browser == slackAppBrowser {
            let teamID = url.pathComponents[2]
            let huddleID = url.pathComponents[3]

            let slackUrl = URL(string: "slack://join-huddle?team=\(teamID)&id=\(huddleID)")!
            let result = slackUrl.openInDefaultBrowser()
            if !result {
                sendNotification("status_bar_error_app_link_title".loco("Slack"), "status_bar_error_app_link_message".loco("Slack"))
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: browser)
        }
    case .facetime:
        NSWorkspace.shared.open(URL(string: "facetime://" + url.absoluteString)!)
    case .facetimeaudio:
        NSWorkspace.shared.open(URL(string: "facetime-audio://" + url.absoluteString)!)
    case .phone:
        NSWorkspace.shared.open(URL(string: "tel://" + url.absoluteString)!)
    case .riverside:
        let browser = browser ?? Defaults[.riversideBrowser]
        if browser == riversideAppBrowser {
            // Try riversidefm:// scheme first
            var riversideAppURL = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            riversideAppURL.scheme = "riversidefm"
            var result = riversideAppURL.url!.openInDefaultBrowser()

            // If that fails, try riverside.fm:// scheme
            if !result {
                riversideAppURL.scheme = "riverside.fm"
                result = riversideAppURL.url!.openInDefaultBrowser()
            }

            // If both app schemes fail, fall back to browser
            if !result {
                sendNotification("status_bar_error_app_link_title".loco("Riverside"), "status_bar_error_app_link_message".loco("Riverside"))
                url.openInDefaultBrowser()
            }
        } else {
            url.openIn(browser: browser)
        }
    default:
        url.openIn(browser: browser ?? Defaults[.defaultBrowser])
    }
}

private nonisolated(unsafe) var iconCache: [MeetingServices?: NSImage] = [:]

func getIconForMeetingService(_ meetingService: MeetingServices?) -> NSImage {
    if let cached = iconCache[meetingService] {
        return cached
    }

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
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.zoom), .some(.zoomgov), .some(.zoom_native):
        image = NSImage(named: "zoom_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.reclaim):
        // reclaim only uses its own links when zoom is involved, so they are always zoom links
        // see https://devforum.zoom.us/t/major-zoom-gcal-sync-problems-recent-behavior-change/80912
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
    case .some(.vimeo):
        image = NSImage(named: "vimeo_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.ovice):
        image = NSImage(named: "ovice_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.facetime), .some(.facetimeaudio):
        image = NSImage(named: "facetime_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.pop):
        image = NSImage(named: "pop_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.chorus):
        image = NSImage(named: "chorus_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.livestorm):
        image = NSImage(named: "livestorm_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.gong):
        image = NSImage(named: "gong_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.preply):
        image = NSImage(named: "preply_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.userzoom):
        image = NSImage(named: "userzoom_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.venue):
        image = NSImage(named: "venue_icon")!
        image.size = NSSize(width: 16, height: 4)

    // tested and verified
    case .some(.teemyco):
        image = NSImage(named: "teemyco_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.demodesk):
        image = NSImage(named: "demodesk_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.zoho_cliq):
        image = NSImage(named: "zoho_cliq_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.slack):
        image = NSImage(named: "slack_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.tuple):
        image = NSImage(named: "tuple_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.pumble):
        image = NSImage(named: "pumble_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.suitConference):
        image = NSImage(named: "suit_conference_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.doxyMe):
        image = NSImage(named: "doxy_me_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.zmPage):
        image = NSImage(named: "zm_page_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.livekit):
        image = NSImage(named: "livekit_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.meetecho):
        image = NSImage(named: "meetecho_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.streamyard):
        image = NSImage(named: "streamyard_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.riverside):
        image = NSImage(named: "riverside_icon")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .none:
        image = NSImage(named: "no_online_session")!
        image.size = NSSize(width: 16, height: 16)

    // tested and verified
    case .some(.vonageMeetings):
        image = NSImage(named: "vonage_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.gather):
        image = NSImage(named: "gather_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.calcom):
        image = NSImage(named: "calcom_icon")!
        image.size = NSSize(width: 16, height: 16)

    case .some(.url):
        image = NSImage(named: NSImage.touchBarOpenInBrowserTemplateName)!
        image.size = NSSize(width: 16, height: 16)

    case .some(.phone):
        image = NSImage(named: NSImage.touchBarCommunicationAudioTemplateName)!
        image.size = NSSize(width: 16, height: 16)

    default:
        break
    }

    iconCache[meetingService] = image
    return image
}
