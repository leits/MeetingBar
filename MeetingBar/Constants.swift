//
//  Constants.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa

struct statusbarEventTitleLengthLimits {
    static let min = 5
    static let max = 55
}

struct TitleTruncationRules {
    static let excludeAtEnds = CharacterSet.whitespacesAndNewlines
}

struct LinksRegex {
    let meet = try! NSRegularExpression(pattern: #"https?://meet.google.com/[a-z-]+"#)
    let hangouts = try! NSRegularExpression(pattern: #"https?://hangouts.google.com/[^\s]*"#)
    let zoom = try! NSRegularExpression(pattern: #"https?:\/\/(?:[a-z0-9-.]+)?zoom.(?:us|com.cn)\/(?:j|my)\/[0-9a-zA-Z?=.]*"#)


    /**
     * Examples:
     * - zoom native links: zoommtg://zoom.us/join?confno=92333341349&uname=Person&pwd=123456
     */
    let zoom_native = try! NSRegularExpression(pattern: #"zoommtg://([a-z0-9-.]+)?zoom\.(us|com\.cn)/join[^\s]*"#)
    let teams = try! NSRegularExpression(pattern: #"https?://teams\.microsoft\.com/l/meetup-join/[a-zA-Z0-9_%\/=\-\+\.?]+"#)
    let webex = try! NSRegularExpression(pattern: #"https?://([a-z0-9-.]+)?webex\.com/[^\s]*"#)
    let jitsi = try! NSRegularExpression(pattern: #"https?://meet\.jit\.si/[^\s]*"#)
    let chime = try! NSRegularExpression(pattern: #"https?://([a-z0-9-.]+)?chime\.aws/[^\s]*"#)
    let ringcentral = try! NSRegularExpression(pattern: #"https?://meetings\.ringcentral\.com/[^\s]*"#)
    let gotomeeting = try! NSRegularExpression(pattern: #"https?://([a-z0-9.]+)?gotomeeting\.com/[^\s]*"#)
    let gotowebinar = try! NSRegularExpression(pattern: #"https?://([a-z0-9.]+)?gotowebinar\.com/[^\s]*"#)
    let bluejeans = try! NSRegularExpression(pattern: #"https?://([a-z0-9.]+)?bluejeans\.com/[^\s]*"#)
    let eight_x_eight = try! NSRegularExpression(pattern: #"https?://8x8\.vc/[^\s]*"#)
    let demio = try! NSRegularExpression(pattern: #"https?://event\.demio\.com/[^\s]*"#)
    let join_me = try! NSRegularExpression(pattern: #"https?://join\.me/[^\s]*"#)
    let zoomgov = try! NSRegularExpression(pattern: #"https?://([a-z0-9.]+)?zoomgov\.com/j/[a-zA-Z0-9?&=]+"#)
    let whereby = try! NSRegularExpression(pattern: #"https?://whereby\.com/[^\s]*"#)
    let uberconference = try! NSRegularExpression(pattern: #"https?://uberconference\.com/[^\s]*"#)
    let blizz = try! NSRegularExpression(pattern: #"https?://go\.blizz\.com/[^\s]*"#)
    let teamviewer_meeting = try! NSRegularExpression(pattern: #"https?://go\.teamviewer\.com/[^\s]*"#)
    let vsee = try! NSRegularExpression(pattern: #"https?://vsee\.com/[^\s]*"#)
    let starleaf = try! NSRegularExpression(pattern: #"https?://meet\.starleaf\.com/[^\s]*"#)
    let duo = try! NSRegularExpression(pattern: #"https?://duo\.app\.goo\.gl/[^\s]*"#)
    let voov = try! NSRegularExpression(pattern: #"https?://voovmeeting\.com/[^\s]*"#)
    let facebook_workspace = try! NSRegularExpression(pattern: #"https?://([a-z0-9-.]+)?workplace\.com/[^\s]+"#)
    let skype = try! NSRegularExpression(pattern: #"https?://join\.skype\.com/[^\s]*"#)
    let skype4biz = try! NSRegularExpression(pattern: #"https?://meet\.lync\.com/[^\s]*"#)
    let skype4biz_selfhosted = try! NSRegularExpression(pattern: #"https?:\/\/(meet|join)\.[^\s]*\/[a-z0-9.]+/meet\/[A-Za-z0-9./]+"#)
    let lifesize = try! NSRegularExpression(pattern: #"https?://call\.lifesizecloud\.com/[^\s]*"#)
    let youtube = try! NSRegularExpression(pattern: #"https?://((www|m)\.)?(youtube\.com|youtu\.be)/[^\s]*"#)
    let vonageMeetings = try! NSRegularExpression(pattern: #"https?://meetings\.vonage\.com/[0-9]{9}"#)
    let meetStream = try! NSRegularExpression(pattern: #"https?://stream\.meet\.google\.com/stream/[a-z0-9-]+"#)
    let around = try! NSRegularExpression(pattern: #"https?://meet\.around\.co/[^\s]*"#)
    let jam = try! NSRegularExpression(pattern: #"https?://jam\.systems/[^\s]*"#)
    let discord = try! NSRegularExpression(pattern: #"(http|https|discord)://(www\.)?(canary\.)?discord(app)?\.([a-zA-Z]{2,})(.+)?"#)
    let blackboard_collab = try! NSRegularExpression(pattern: #"https?://us\.bbcollab\.com/[^\s]*"#)
}

enum CreateMeetingLinks {
    static var meet = URL(string: "https://meet.google.com/new")!
    static var zoom = URL(string: "https://zoom.us/start?confno=123456789&zc=0")!
    static var teams = URL(string: "https://teams.microsoft.com/l/meeting/new?subject=")!
    static var jam = URL(string: "https://jam.systems/new")!
    static var gcalendar = URL(string: "https://calendar.google.com/calendar/u/0/r/eventedit")!
    static var outlook_live = URL(string: "https://outlook.live.com/calendar/0/action/compose")!
    static var outlook_office365 = URL(string: "https://outlook.office365.com/calendar/0/action/compose")!
}

enum CreateMeetingServices: String, Codable, CaseIterable {
    case meet = "Google Meet"
    case zoom = "Zoom"
    case teams = "Microsoft Teams"
    case jam = "Jam"
    case gcalendar = "Google Calendar"
    case outlook_live = "Outlook Live"
    case outlook_office365 = "Outlook Office365"
    case url = "Custom url"

    var localizedValue: String {
        switch self {
        case .meet: return "constants_create_meeting_service_meet".loco()
        case .hangouts: return "constants_create_meeting_service_hangouts".loco()
        case .zoom: return "constants_create_meeting_service_zoom".loco()
        case .teams: return "constants_create_meeting_service_teams".loco()
        case .gcalendar: return "constants_create_meeting_service_gcalendar".loco()
        case .outlook_live: return "constants_create_meeting_service_outlook_live".loco()
        case .outlook_office365: return "constants_create_meeting_service_outlook_office365".loco()
        case .url: return "constants_create_meeting_service_url".loco()
        }
    }
}

enum Links {
    static var patreon = URL(string: "https://www.patreon.com/meetingbar")!
    static var github = URL(string: "https://github.com/leits/MeetingBar")!
    static var telegram = URL(string: "https://t.me/leits")!
    static var twitter = URL(string: "https://twitter.com/leits_dev")!
    static var emailMe = URL(string: "mailto:leits.dev@gmail.com?subject=MeetingBar")!
    static var calendarPreferences = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
}

enum MeetingServices: String, Codable, CaseIterable {
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
    case facetimeaudio = "Facetime Audio"
    case youtube = "YouTube"
    case vonageMeetings = "Vonage Meetings"
    case meetStream = "Google Meet Stream"
    case around = "Around"
    case jam = "Jam"
    case discord = "Discord"
    case blackboard_collab = "Blackboard Collaborate"
    case other = "Other"

    var localizedValue: String {
        switch self {
        case .phone: return "constants_meeting_service_phone".loco()
        case .meet: return "constants_meeting_service_meet".loco()
        case .hangouts: return "constants_meeting_service_hangouts".loco()
        case .zoom: return "constants_meeting_service_zoom".loco()
        case .zoom_native: return "constants_meeting_service_zoom_native".loco()
        case .teams: return "constants_meeting_service_teams".loco()
        case .webex: return "constants_meeting_service_webex".loco()
        case .jitsi: return "constants_meeting_service_jitsi".loco()
        case .chime: return "constants_meeting_service_chime".loco()
        case .ringcentral: return "constants_meeting_service_ringcentral".loco()
        case .gotomeeting: return "constants_meeting_service_gotomeeting".loco()
        case .gotowebinar: return "constants_meeting_service_gotowebinar".loco()
        case .bluejeans: return "constants_meeting_service_bluejeans".loco()
        case .eight_x_eight: return "constants_meeting_service_eight_x_eight".loco()
        case .demio: return "constants_meeting_service_demio".loco()
        case .join_me: return "constants_meeting_service_join_me".loco()
        case .zoomgov: return "constants_meeting_service_zoomgov".loco()
        case .whereby: return "constants_meeting_service_whereby".loco()
        case .uberconference: return "constants_meeting_service_uberconference".loco()
        case .blizz: return "constants_meeting_service_blizz".loco()
        case .teamviewer_meeting: return "constants_meeting_service_teamviewer_meeting".loco()
        case .vsee: return "constants_meeting_service_vsee".loco()
        case .starleaf: return "constants_meeting_service_starleaf".loco()
        case .duo: return "constants_meeting_service_duo".loco()
        case .voov: return "constants_meeting_service_voov".loco()
        case .facebook_workspace: return "constants_meeting_service_facebook_workspace".loco()
        case .lifesize: return "constants_meeting_service_lifesize".loco()
        case .skype: return "constants_meeting_service_skype".loco()
        case .skype4biz: return "constants_meeting_service_skype4biz".loco()
        case .skype4biz_selfhosted: return "constants_meeting_service_skype4biz_selfhosted".loco()
        case .facetime: return "constants_meeting_service_facetime".loco()
        case .facetimeaudio: return "constants_meeting_service_facetimeaudio".loco()
        case .youtube: return "constants_meeting_service_youtube".loco()
        case .vonageMeetings: return "constants_meeting_service_vonageMeetings".loco()
        case .meetStream: return "constants_meeting_service_meetStream".loco()
        case .around: return "constants_meeting_service_around".loco()
        case .jam: return "constants_meeting_service_jam".loco()
        case .discord: return "constants_meeting_service_discord".loco()
        case .other: return "constants_meeting_service_other".loco()
        }
    }
}

enum TimeFormat: String, Codable, CaseIterable {
    case am_pm = "12-hour"
    case military = "24-hour"
}

/**
 * the icon to display in the status bar
 */
enum EventTitleIconFormat: String, Codable, CaseIterable {
    case calendar = "iconCalendar"
    case appicon = "AppIcon"
    case eventtype = "ms_teams_icon"
    case none = "no_online_session"
}

enum EventTitleFormat: String, Codable, CaseIterable {
    case show
    case dot
    case none
}

/**
 * format for time in statusbar - can be shown, be under title or be hidden
 */
enum EventTimeFormat: String, Codable, CaseIterable {
    case show
    case show_under_title
    case hide
}

enum DeclinedEventsAppereance: String, Codable, CaseIterable {
    case strikethrough
    case show_inactive
    case hide
}

enum AlldayEventsAppereance: String, Codable, CaseIterable {
    case show
    case show_with_meeting_link_only
    case hide
}

enum PendingEventsAppereance: String, Codable, CaseIterable {
    case show
    case show_inactive
    case show_underlined
    case hide
}

enum PastEventsAppereance: String, Codable, CaseIterable {
    case show_active
    case show_inactive
    case hide
}

enum ShowEventsForPeriod: String, Codable, CaseIterable {
    case today
    case today_n_tomorrow
}

enum JoinEventNotificationTime: Int, Codable {
    case atStart = 5
    case minuteBefore = 60
    case threeMinuteBefore = 180
    case fiveMinuteBefore = 300
}

enum UtilsRegex {
    static let emailAddress = try! NSRegularExpression(pattern: #""mailto:(.+@.+)""#)
    static let outlookSafeLinkRegex = try! NSRegularExpression(pattern: #"https://[\S]+\.safelinks\.protection\.outlook\.com/[\S]+url=([\S]*)"#)
}

public enum AutoLauncher {
    static let bundleIdentifier: String = "leits.MeetingBar.AutoLauncher"
}

enum AppLanguage: String, Codable {
    case system = ""
    case english = "en"
    case russian = "ru"
}

enum Browser: String, Codable, CaseIterable {
    case chrome = "Google Chrome"
    case firefox = "Firefox"
    case safari = "Safari"
    case chromium = "Chromium"
    case brave = "Brave"
    case edge = "Microsoft Edge"
    case opera = "Opera"
    case vivaldi = "Vivaldi"
    case defaultBrowser = "Default Browser"

    var url: URL? {
        switch self {
        case .chrome:
            return URL(fileURLWithPath: "/Applications/Google Chrome.app")

        case .firefox:
            return URL(fileURLWithPath: "/Applications/Firefox.app")

        case .safari:
            return URL(fileURLWithPath: "/Applications/Safari.app")

        case .chromium:
            return URL(fileURLWithPath: "/Applications/Chromium.app")

        case .brave:
            return URL(fileURLWithPath: "/Applications/Brave Browser.app")

        case .edge:
            return URL(fileURLWithPath: "/Applications/Microsoft Edge.app")

        case .opera:
            return URL(fileURLWithPath: "/Applications/Opera.app")

        case .vivaldi:
            return URL(fileURLWithPath: "/Applications/Vivaldi.app")

        default:
            return nil
        }
    }

    var localizedValue: String {
        switch self {
        case .brave: return "constants_browser_brave".loco()
        case .chrome: return "constants_browser_chrome".loco()
        case .chromium: return "constants_browser_chromium".loco()
        case .edge: return "constants_browser_edge".loco()
        case .firefox: return "constants_browser_firefox".loco()
        case .opera: return "constants_browser_opera".loco()
        case .vivaldi: return "constants_browser_vivaldi".loco()
        case .defaultBrowser: return "constants_browser_defaultBrowser".loco()
        }
    }
}


struct windowTitles {
    static let onboarding = "Welcome to MeetingBar!"
    static let preferences = "MeetingBar Preferences"
    static let changelog = "MeetingBar What's New"
}
