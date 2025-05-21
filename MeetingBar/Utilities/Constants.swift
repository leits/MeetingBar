//
//  Constants.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import Defaults

let systemDefaultBrowser = Browser(name: "preferences_services_link_default_browser_value".loco(), path: "")
let meetInOneBrowser = Browser(name: "MeetInOne", path: "")
let zoomAppBrowser = Browser(name: "Zoom", path: "")
let teamsAppBrowser = Browser(name: "Teams", path: "")
let jitsiAppBrowser = Browser(name: "Jitsi", path: "")
let slackAppBrowser = Browser(name: "Slack", path: "")

enum statusbarEventTitleLengthLimits {
    static let min = 5
    static let max = 55
}

enum TitleTruncationRules {
    static let excludeAtEnds = CharacterSet.whitespacesAndNewlines
}

enum Links {
    static let patreon = URL(string: "https://www.patreon.com/meetingbar")!
    static let buymeacoffee = URL(string: "https://www.buymeacoffee.com/meetingbar")!
    static let github = URL(string: "https://github.com/leits/MeetingBar")!
    static let telegram = URL(string: "https://t.me/leits")!
    static let twitter = URL(string: "https://twitter.com/leits_dev")!
    static let emailMe = URL(string: "mailto:leits.dev@gmail.com?subject=MeetingBar")!
    static let calendarPreferences = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    static let rateAppInAppStore = URL(string: "itms-apps://apps.apple.com/app/id1532419400?action=write-review")!
}

enum TimeFormat: String, Defaults.Serializable, Codable, CaseIterable {
    case am_pm = "12-hour"
    case military = "24-hour"
}

/// the icon to display in the status bar
enum EventTitleIconFormat: String, Defaults.Serializable, Codable, CaseIterable {
    case calendar = "iconCalendar"
    case appicon = "AppIcon"
    case eventtype = "ms_teams_icon"
    case none = "no_online_session"
}

enum EventTitleFormat: String, Defaults.Serializable, Codable, CaseIterable {
    case show
    case dot
    case none
}

/// format for time in statusbar - can be shown, be under title or be hidden
enum EventTimeFormat: String, Defaults.Serializable, Codable, CaseIterable {
    case show
    case show_under_title
    case hide
}

enum DeclinedEventsAppereance: String, Defaults.Serializable, Codable, CaseIterable {
    case strikethrough
    case show_inactive
    case hide
}

enum AlldayEventsAppereance: String, Defaults.Serializable, Codable, CaseIterable {
    case show
    case show_with_meeting_link_only
    case hide
}

enum NonAlldayEventsAppereance: String, Defaults.Serializable, Codable, CaseIterable {
    case show
    case show_inactive_without_meeting_link
    case hide_without_meeting_link
}

enum PendingEventsAppereance: String, Defaults.Serializable, Codable, CaseIterable {
    case show
    case show_inactive
    case show_underlined
    case hide
}

enum TentativeEventsAppereance: String, Defaults.Serializable, Codable, CaseIterable {
    case show
    case show_inactive
    case show_underlined
    case hide
}

enum PastEventsAppereance: String, Defaults.Serializable, Codable, CaseIterable {
    case show_active
    case show_inactive
    case hide
}

enum ShowEventsForPeriod: String, Defaults.Serializable, Codable, CaseIterable {
    case today
    case today_n_tomorrow
}

enum OngoingEventVisibility: String, Defaults.Serializable, Codable, CaseIterable {
    case hideImmediateAfter
    case showTenMinAfter
    case showTenMinBeforeNext
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
        durationInSeconds / 60
    }
}

enum TimeBeforeEvent: Int, Defaults.Serializable, Codable {
    case atStart = 5
    case minuteBefore = 60
    case threeMinuteBefore = 180
    case fiveMinuteBefore = 300
}

enum TimeBeforeEventEnd: Int, Defaults.Serializable, Codable {
    case atEnd = 5
    case minuteBefore = 60
    case threeMinuteBefore = 180
    case fiveMinuteBefore = 300
}

enum UtilsRegex {
    static let outlookSafeLinkRegex = try! NSRegularExpression(pattern: #"https://[\S]+\.safelinks\.protection\.outlook\.com/[\S]+url=([\S]*)"#)
    static let linkDetection = try! NSRegularExpression(pattern: #"(http|ftp|https)://([\w_-]+(?:(?:\.[\w_-]+)+))([\w.,@?^=%&:/~+#-]*[\w@?^=%&/~+#-])?"#, options: .caseInsensitive)
}

enum AppLanguage: String, Defaults.Serializable, Codable {
    case system = ""
    case english = "en"
    case ukrainian = "ua"
    case croatian = "hr"
    case german = "de"
    case french = "fr"
    case czech = "cs"
    case norwegian = "nb-NO"
    case japanese = "ja"
    case polish = "pl"
    case hebrew = "he"
    case turkish = "tr"
    case italian = "it"
    case portuguese = "pt-BR"
    case spanish = "es"
    case slovak = "sk"
    case dutch = "nl"
}

struct Browser: Defaults.Serializable, Codable, Hashable {
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

enum notificationIDs {
    static let event_starts = "NEXT_EVENT"
    static let event_ends = "EVENT_ENDS"
}

let eventStartScriptPlaceholder = """
# the method to be called with the following parameters for the next meeting.
#
# 1. parameter - eventId (string) - unique identifier from apples eventkit implementation
# 2. parameter - title (string) - the title of the event (event title can be null, although it makes no sense!)
# 3. parameter - allday (bool) - true for allday events, false for non allday events
# 4. parameter - startDate (date) - needs casting in apple script to output (e.g. startDate as text)
# 5 .parameter - endDate (date) - needs casting in apple script to output (e.g. startDate as text)
# 6. parameter - eventLocation (string) - if no location is set, the value will be "EMPTY"
# 7. parameter - repeatingEvent (bool) - true if it is part of an repeating event, false for single event
# 8. parameter - attendeeCount (int32) - number of attendees- 0 for events without attendees
# 9. parameter - meetingUrl (string) - the url to the meeting found in notes, url or location - only one meeting url is supported - if no meeting url is set, the value will be "EMPTY"
# 10. parameter - meetingService (string), e.g MS Teams or Zoom- if no meeting service is found, the meeting service value is "EMPTY"
# 11. parameter - meetingNotes (string)- the complete notes of a meeting -  if no notes are set, value "EMPTY" will be used

on meetingStart(eventId, title, allday, startDate, endDate, eventLocation, repeatingEvent, attendeeCount, meetingUrl, meetingService, meetingNotes)
   tell application "Finder"
       activate
       display dialog title buttons {"OK"} default button "OK"
   end tell
end meetingStart
"""
