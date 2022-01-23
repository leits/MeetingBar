//
//  Constants.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa

var systemDefaultBrowser = Browser(name: "Default Browser", path: "")
var MeetInOneBrowser = Browser(name: "MeetInOne", path: "")

enum statusbarEventTitleLengthLimits {
    static let min = 5
    static let max = 55
}

enum TitleTruncationRules {
    static let excludeAtEnds = CharacterSet.whitespacesAndNewlines
}

struct LinksRegex {
    let meet = try! NSRegularExpression(pattern: #"https?://meet.google.com/[a-z-]+"#)
    let hangouts = try! NSRegularExpression(pattern: #"https?://hangouts.google.com/[^\s]*"#)
    let zoom = try! NSRegularExpression(pattern: #"https?:\/\/(?:[a-zA-Z0-9-.]+)?zoom.(?:us|com.cn)\/(?:j|my|w)\/[-a-zA-Z0-9()@:%_\+.~#?&=\/]*"#)

    /**
     * Examples:
     * - zoom native links: zoommtg://zoom.us/join?confno=92333341349&uname=Person&pwd=123456
     */
    let zoom_native = try! NSRegularExpression(pattern: #"zoommtg://([a-z0-9-.]+)?zoom\.(us|com\.cn)/join[-a-zA-Z0-9()@:%_\+.~#?&=\/]*"#)
    let teams = try! NSRegularExpression(pattern: #"https?://teams\.microsoft\.com/l/meetup-join/[a-zA-Z0-9_%\/=\-\+\.?]+"#)
    let webex = try! NSRegularExpression(pattern: #"https?://([a-z0-9-.]+)?webex\.com/[^\s]*"#)
    let jitsi = try! NSRegularExpression(pattern: #"https?://meet\.jit\.si/[^\s]*"#)
    let chime = try! NSRegularExpression(pattern: #"https?://([a-z0-9-.]+)?chime\.aws/[^\s]*"#)
    let ringcentral = try! NSRegularExpression(pattern: #"https?://([a-z0-9.]+)?ringcentral\.com/[^\s]*"#)
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
    let coscreen = try! NSRegularExpression(pattern: #"https?://join\.coscreen\.co/[^\s]*"#)
    let vowel = try! NSRegularExpression(pattern: #"https?://([a-z0-9.]+)?vowel\.com/#/g/[^\s]*"#)
    let zhumu = try! NSRegularExpression(pattern: #"https://welink\.zhumu\.com/j/[0-9]+?pwd=[a-zA-Z0-9]+"#)
    let lark = try! NSRegularExpression(pattern: #" https://vc\.larksuite\.com/j/[0-9]+"#)
    let feishu = try! NSRegularExpression(pattern: #"https://vc\.feishu\.cn/j/[0-9]+"#)
    let vimeo_showcases = try! NSRegularExpression(pattern: #"https://vimeo\.com/showcase/[0-9]+"#)
    let ovice = try! NSRegularExpression(pattern: #"https://([a-z0-9-.]+)?ovice\.in/[^\s]*"#)
}

enum CreateMeetingLinks {
    static var meet = URL(string: "https://meet.google.com/new")!
    static var zoom = URL(string: "https://zoom.us/start?confno=123456789&zc=0")!
    static var teams = URL(string: "https://teams.microsoft.com/l/meeting/new?subject=")!
    static var jam = URL(string: "https://jam.systems/new")!
    static var coscreen = URL(string: "https://cs.new")!
    static var gcalendar = URL(string: "https://calendar.google.com/calendar/u/0/r/eventedit")!
    static var outlook_live = URL(string: "https://outlook.live.com/calendar/0/action/compose")!
    static var outlook_office365 = URL(string: "https://outlook.office365.com/calendar/0/action/compose")!
}

enum CreateMeetingServices: String, Codable, CaseIterable {
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
    case url = "Any Link"
    case coscreen = "CoScreen"
    case vowel = "Vowel"
    case zhumu = "Zhumu"
    case lark = "Lark"
    case feishu = "Feishu"
    case vimeo_showcases = "Vimeo Showcases"
    case ovice = "oVice"
    case other = "Other"

    var localizedValue: String {
        switch self {
        case .phone:
            return "constants_meeting_service_phone".loco()
        case .zoom_native:
            return "constants_meeting_service_zoom_native".loco()
        case .skype4biz:
            return "constants_meeting_service_skype4biz".loco()
        case .skype4biz_selfhosted:
            return "constants_meeting_service_skype4biz_selfhosted".loco()
        case .other:
            return "constants_meeting_service_other".loco()
        case .url:
            return "constants_meeting_service_url".loco()
        default:
            return rawValue
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

enum NonAlldayEventsAppereance: String, Codable, CaseIterable {
    // show all non all day events - no special requirement
    case show

    // deactivates all non all day events when no meeting link is detected
    case show_inactive_without_meeting_link

    // hides all non all day events when no meeting link is detected
    case hide_without_meeting_link
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
    case ukrainian = "ua"
    case russian = "ru"
    case croatian = "hr"
    case german = "de"
    case french = "fr"
    case czech = "cs"
    case norwegian = "nb-NO"
    case japanese = "ja"
    case polish = "pl"
    case hebrew = "he"
    case turkish = "tr"
}

struct Browser: Encodable, Decodable, Hashable {
    var name: String
    var path: String
    var arguments: String = ""
    var deletable = true
}

enum DeprecatedBrowser: String, Codable, CaseIterable {
    case chrome = "Google Chrome"
    case firefox = "Firefox"
    case safari = "Safari"
    case chromium = "Chromium"
    case brave = "Brave"
    case edge = "Microsoft Edge"
    case opera = "Opera"
    case vivaldi = "Vivaldi"
    case defaultBrowser = "Default Browser"
}

enum WindowTitles {
    static let onboarding = "window_title_onboarding".loco()
    static let preferences = "window_title_preferences".loco()
    static let changelog = "windows_title_changelog".loco()
}
