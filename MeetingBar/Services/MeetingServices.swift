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
    MeetingOpenerRegistry.strategy(for: service).open(url: url, browser: browser)
}

private nonisolated(unsafe) var iconCache: [MeetingServices?: NSImage] = [:]

func getIconForMeetingService(_ meetingService: MeetingServices?) -> NSImage {
    if let cached = iconCache[meetingService] {
        return cached
    }

    var image: NSImage
    if let service = meetingService,
       let descriptor = MeetingProviderRegistry.descriptor(for: service) {
        image = NSImage(named: descriptor.iconName) ?? NSImage(named: "no_online_session")!
        image.size = NSSize(width: descriptor.iconWidth, height: descriptor.iconHeight)
    } else {
        image = NSImage(named: "no_online_session")!
        image.size = NSSize(width: 16, height: 16)
    }

    iconCache[meetingService] = image
    return image
}
