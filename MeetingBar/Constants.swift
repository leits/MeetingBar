//
//  Constants.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa

struct TitleLengthLimits {
    static let min = 0.0
    static let max = 55.0
}

struct LinksRegex {
    static let teams = try! NSRegularExpression(pattern: #"https://teams.microsoft.com/l/meetup-join/[a-zA-Z0-9_%\/=\-\+\.?]+"#)
    static let meet = try! NSRegularExpression(pattern: #"https://meet.google.com/[a-z-]+"#)
    static let hangouts = try! NSRegularExpression(pattern: #"https://hangouts.google.com.*"#)
    static let zoom = try! NSRegularExpression(pattern: #"https://([a-z0-9.]+)?zoom.us/j/[a-zA-Z0-9?&=]+"#)
    static let teams = try! NSRegularExpression(pattern: #"https://teams.microsoft.com/l/meetup-join/[a-zA-Z0-9_%\/=\-\+\.?]+"#)
}

struct Links {
    static var newMeetMeeting = URL(string: "https://meet.google.com/new")!
    static var newHangoutsMeeting = URL(string: "https://hangouts.google.com/call")!
    static var newZoomMeeting = URL(string: "https://zoom.us/start/videomeeting")!
    static var newTeamsMeeting = URL(string: "https://teams.microsoft.com/l/meeting/new")!
    static var supportTheCreator = URL(string: "https://www.patreon.com/meetingbar")!
    static var aboutThisApp = URL(string: "https://meetingbar.onrender.com")!
}

enum MeetingServices: String, Codable, CaseIterable {
    case meet = "Google Meet"
    case zoom = "Zoom"
    case teams = "Microsoft Teams"
    case hangouts = "Google Hangouts"
}

enum TimeFormat: String, Codable, CaseIterable {
    case am_pm = "12-hour"
    case military = "24-hour"
}

enum AuthResult {
    case success(Bool), failure(Error)
}

enum ETAFormat: String, Codable, CaseIterable {
    case short = "short"
    case full = "full"
    case abbreviated = "abbreviated"
}

enum EventTitleFormat: String, Codable, CaseIterable {
    case show = "show"
    case hide = "hide"
    case dot = "dot"
}

enum DeclinedEventsAppereance: String, Codable, CaseIterable {
    case strikethrough = "strikethrough"
    case hide = "hide"
}
