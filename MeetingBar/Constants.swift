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

enum Links {
    static var patreon = URL(string: "https://www.patreon.com/meetingbar")!
    static var github = URL(string: "https://github.com/leits/MeetingBar")!
    static var telegram = URL(string: "https://t.me/leits")!
    static var twitter = URL(string: "https://twitter.com/leits_dev")!
    static var emailMe = URL(string: "mailto:leits.dev@gmail.com?subject=MeetingBar")!
    static var calendarPreferences = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
}

enum TimeFormat: String, Codable, CaseIterable {
    case am_pm = "12-hour"
    case military = "24-hour"
}

/// the icon to display in the status bar
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

/// format for time in statusbar - can be shown, be under title or be hidden
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
    case show
    case show_inactive_without_meeting_link
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

enum NotificationEventTimeAction: String, Codable {
    case untilStart = "SNOOZE_UNTIL_START_TIME"
    case fiveMinuteLater = "SNOOZE_FOR_5_MIN"
    case tenMinuteLater = "SNOOZE_FOR_10_MIN"
    case fifteenMinuteLater = "SNOOZE_FOR_15_MIN"
    case thirtyMinuteLater = "SNOOZE_FOR_30_MIN"

    var durationInSeconds: Int {
        switch self {
        case .untilStart:
            return 0
        case .fiveMinuteLater:
            return 300
        case .tenMinuteLater:
            return 600
        case .fifteenMinuteLater:
            return 900
        case .thirtyMinuteLater:
            return 1800
        }
    }

    var durationInMins: Int {
        return durationInSeconds / 60
    }
}

enum UtilsRegex {
    static let emailAddress = try! NSRegularExpression(pattern: #"(\S+@\S+)"#)
    static let outlookSafeLinkRegex = try! NSRegularExpression(pattern: #"https://[\S]+\.safelinks\.protection\.outlook\.com/[\S]+url=([\S]*)"#)
    static let linkDetection = try! NSRegularExpression(pattern: #"(http|ftp|https)://([\w_-]+(?:(?:\.[\w_-]+)+))([\w.,@?^=%&:/~+#-]*[\w@?^=%&/~+#-])?"#, options: .caseInsensitive)
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

enum WindowTitles {
    static let onboarding = "window_title_onboarding".loco()
    static let preferences = "window_title_preferences".loco()
    static let changelog = "windows_title_changelog".loco()
}
