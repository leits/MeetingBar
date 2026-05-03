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
    let service = Defaults[.createMeetingService]

    if service == .url {
        var url: String = Defaults[.createMeetingServiceUrl]
        if !url.isEmpty, NSURL(string: url) != nil {
            openMeetingURL(nil, URL(string: url)!, browser)
        } else {
            if !url.isEmpty { url += " " }
            sendNotification("create_meeting_error_title".loco(), "create_meeting_error_message".loco(url))
        }
        return
    }

    if let descriptor = CreateMeetingRegistry.descriptor(for: service) {
        openMeetingURL(descriptor.meetingService, descriptor.url, browser)
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
