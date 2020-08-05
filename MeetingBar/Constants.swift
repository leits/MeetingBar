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
    static let zoom = try! NSRegularExpression(pattern: #"https://([a-z0-9.]+)?zoom.us/j/[a-zA-Z0-9?&=]+"#)
}

struct Links {
    static var newMeetMeeting = URL(string: "https://meet.google.com/new")!
    static var newZoomMeeting = URL(string: "https://zoom.us/start/videomeeting")!
    static var newTeamsMeeting = URL(string: "msteams://teams.microsoft.com/l/meeting/new?subject=")! // see https://docs.microsoft.com/en-us/microsoftteams/platform/concepts/build-and-test/deep-links
    static var supportTheCreator = URL(string: "https://www.patreon.com/meetingbar")!
    static var aboutThisApp = URL(string: "https://github.com/leits/MeetingBar")!
}

enum MeetingServices: String, Codable, CaseIterable {
    case meet = "Google Meet"
    case zoom = "Zoom"
    case teams = "Microsoft Teams"
}

enum TimeFormat: String, Codable, CaseIterable {
    case am_pm = "12-hour"
    case military = "24-hour"
}

enum AuthResult {
    case success(Bool), failure(Error)
}
