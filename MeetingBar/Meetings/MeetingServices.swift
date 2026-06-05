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

// `MeetingServices` enum lives in `MeetingLinkDetector.swift` so it can be
// reached from the hostless logic target. This file only carries the
// production-side extensions (icons, localisation, opening, create-meeting).

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
            AppMessageCenter.shared.post(.createMeetingInvalidURL(value: url))
        }
        return
    }

    if let descriptor = createMeetingDescriptor(for: service) {
        openMeetingURL(descriptor.meetingService, descriptor.url, browser)
    }
}

func openMeetingURL(_ service: MeetingServices?, _ url: URL, _ browser: Browser?) {
    openStrategy(for: service).open(url: url, browser: browser)
}

// MARK: - Create-meeting descriptors

/// Where to open a brand-new meeting for each create-meeting service.
/// `.url` is handled in `createMeeting()` because it requires runtime input.
private struct CreateMeetingDescriptor {
    let url: URL
    let meetingService: MeetingServices?
}

private func createMeetingDescriptor(for service: CreateMeetingServices) -> CreateMeetingDescriptor? {
    switch service {
    case .meet:
        return CreateMeetingDescriptor(
            url: URL(string: "https://meet.google.com/new")!, meetingService: .meet)
    case .zoom:
        return CreateMeetingDescriptor(
            url: URL(string: "https://zoom.us/start?confno=123456789&zc=0")!,
            meetingService: .zoom)
    case .teams:
        return CreateMeetingDescriptor(
            url: URL(string: "https://teams.microsoft.com/l/meeting/new?subject=")!,
            meetingService: .teams)
    case .jam:
        return CreateMeetingDescriptor(
            url: URL(string: "https://jam.systems/new")!, meetingService: .jam)
    case .coscreen:
        return CreateMeetingDescriptor(
            url: URL(string: "https://cs.new")!, meetingService: .coscreen)
    case .gcalendar:
        return CreateMeetingDescriptor(
            url: URL(string: "https://calendar.google.com/calendar/u/0/r/eventedit")!,
            meetingService: nil)
    case .outlook_live:
        return CreateMeetingDescriptor(
            url: URL(string: "https://outlook.live.com/calendar/0/action/compose")!,
            meetingService: nil)
    case .outlook_office365:
        return CreateMeetingDescriptor(
            url: URL(string: "https://outlook.office365.com/calendar/0/action/compose")!,
            meetingService: nil)
    case .url:
        return nil
    }
}

private nonisolated(unsafe) var iconCache: [MeetingServices?: NSImage] = [:]

func getIconForMeetingService(_ meetingService: MeetingServices?) -> NSImage {
    if let cached = iconCache[meetingService] {
        return cached
    }

    var image: NSImage
    if let service = meetingService,
        let provider = MeetingProvider.provider(for: service) {
        image = NSImage(named: provider.iconName) ?? NSImage(named: "no_online_session")!
        image.size = NSSize(width: provider.iconWidth, height: provider.iconHeight)
    } else {
        image = NSImage(named: "no_online_session")!
        image.size = NSSize(width: 16, height: 16)
    }

    iconCache[meetingService] = image
    return image
}
