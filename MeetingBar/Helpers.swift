//
//  Helpers.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import Cocoa
import EventKit
import Defaults

struct EventWithDate {
    let event: EKEvent
    let dateSection: Date
}

struct MeetingLink: Equatable {
    let service: MeetingServices?
    var url: URL
}

struct Bookmark: Encodable, Decodable, Hashable {
    var name: String
    var service: MeetingServices
    var url: String
}

/**
 * this method will extract m365 safe links if any of these links are found in the given text..
 * The method will extract the real url from safe links and decode it, so that the following regex logic can detect the meeting service.
 *
 * The original link looks like this
 *https://nam12.safelinks.protection.outlook.com/ap/t-59584e83/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_[obfuscated]&data=[obfuscated]
 *
 * and the method will extract it to https://teams.microsoft.com/l/meetup-join/19%3ameeting_[obfuscated]
 * If no m365 links are found, the original text is returned.
 *
 */
fileprivate func cleanupOutlookSafeLinks( text: inout String) -> String {
    NSLog("Check text \(text) for outlook safe links")

    var links = UtilsRegex.outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    if !links.isEmpty {
        repeat {
            let urlRange = links[0].range( at: 1)
            let safeLinks = links.map { String(text[Range($0.range, in: text)!]) }
            if !safeLinks.isEmpty {
                let serviceUrl = (text as NSString).substring(with: urlRange)
                NSLog("Found service url \(serviceUrl)")
                text = text.replacingOccurrences(of: safeLinks[0], with: serviceUrl.decodeUrl()!)
            }
            links = UtilsRegex.outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        } while !links.isEmpty
    }

    NSLog("Returning text \(text)")
    return text
}

func getMatch(text: String, regex: NSRegularExpression) -> String? {
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range, in: text)!]) }

    if !resultsMap.isEmpty {
        let match = resultsMap[0]
        return match
    }
    return nil
}


func cleanUpNotes(_ notes: String) -> String {
    let zoomSeparator = "\n──────────"
    let meetSeparator = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
    let cleanNotes = notes
        .components(separatedBy: zoomSeparator)[0]
        .components(separatedBy: meetSeparator)[0]
        .htmlTagsStripped()
    return cleanNotes
}

func getRegexForService(_ service: MeetingServices) -> NSRegularExpression? {
    let regexes = LinksRegex()
    let mirror = Mirror(reflecting: regexes)

    for child in mirror.children {
        if child.label == String(describing: service) {
            return child.value as? NSRegularExpression
        }
    }
    return nil
}

func getGmailAccount(_ event: EKEvent) -> String? {
    // Hacky and likely to break, but should work until Apple changes something
    let regex = UtilsRegex.emailAddress
    let text = event.calendar.source.description
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range(at: 1), in: text)!]) }
    if !resultsMap.isEmpty {
        return resultsMap.first
    }
    return nil
}

func detectLink(_ field: inout String) -> MeetingLink? {
    _ = cleanupOutlookSafeLinks(text: &field)

    for pattern in Defaults[.customRegexes] {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            if let link = getMatch(text: field, regex: regex) {
                if let url = URL(string: link) {
                    return MeetingLink(service: MeetingServices.other, url: url)
                }
            }
        }
    }

    for service in MeetingServices.allCases {
        if let regex = getRegexForService(service) {
            if let link = getMatch(text: field, regex: regex) {
                if let url = URL(string: link) {
                    return MeetingLink(service: service, url: url)
                }
            }
        }
    }
    return nil
}

/**
 * this method will collect text from the location, url and notes field of an event and try to find a known meeting url link.
 * As meeting links can be part of a outlook safe url, we will extract the original link from outlook safe links.
 */
func getMeetingLink(_ event: EKEvent, acceptAnyLink: Bool) -> MeetingLink? {
    var linkFields: [String] = []

    if let location = event.location {
        linkFields.append(location)
    }

    if let url = event.url {
        linkFields.append(url.absoluteString)
    }

    if let notes = event.notes {
        linkFields.append(notes)
    }


    for var field in linkFields {
        var meetingLink = detectLink(&field)
        if meetingLink != nil {
            if meetingLink?.service == .meet,
               let account = getGmailAccount(event),
               let urlEncodedAccount = account.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                let url = URL(string: (meetingLink?.url.absoluteString)! + "?authuser=\(urlEncodedAccount)")!
                    meetingLink?.url = url
            }
            return meetingLink
        }
    }

    if acceptAnyLink {
        for var field in linkFields {
            let links = detectLinks(text: field)
            if !links.isEmpty {
                return MeetingLink(service: MeetingServices.url, url: links[0])
            }
        }
    }



    return nil
}

func detectLinks(text: String) -> [URL] {
    let types: NSTextCheckingResult.CheckingType = .link

    do {
        let detector = try NSDataDetector(types: types.rawValue)

        let matches = detector.matches(in: text, options: .reportCompletion, range: NSRange(location: 0, length: text.count))
        return matches.compactMap { $0.url }
    } catch {
        debugPrint(error.localizedDescription)
    }

    return []
}


func openEvent(_ event: EKEvent) {
    let eventTitle = event.title ?? "No title"
    if let meeting = getMeetingLink(event, acceptAnyLink: Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.hide_without_any_link || Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.show_inactive_without_any_link) {
        if Defaults[.runJoinEventScript], Defaults[.joinEventScriptLocation] != nil {
            if let url = Defaults[.joinEventScriptLocation]?.appendingPathComponent("joinEventScript.scpt") {
                print("URL: \(url)")
                let task = try! NSUserAppleScriptTask(url: url)
                task.execute { error in
                    if let error = error {
                        sendNotification("AppleScript return error", error.localizedDescription)
                    }
                }
            }
        }
        openMeetingURL(meeting.service, meeting.url)
    } else {
        sendNotification("Epp! Can't join the \(eventTitle)", "Link not found, or your meeting service is not yet supported")
    }
}

func getEventParticipantStatus(_ event: EKEvent) -> EKParticipantStatus? {
    if event.hasAttendees {
        if let attendees = event.attendees {
            if let currentUser = attendees.first(where: { $0.isCurrentUser }) {
                return currentUser.participantStatus
            }
        }
    }
    return EKParticipantStatus.unknown
}


func openMeetingURL(_ service: MeetingServices?, _ url: URL) {
    switch service {
    case .meet:
        let browser = Defaults[.browserForMeetLinks]
        url.openIn(browser: browser)

    case .teams:
        if Defaults[.useAppForTeamsLinks] {
            var teamsAppURL = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            teamsAppURL.scheme = "msteams"
            let result = teamsAppURL.url!.openInDefaultBrowser()
            if !result {
                sendNotification("Oops! Unable to open the link in Microsoft Teams app", "Make sure you have Microsoft Teams app installed, or change the app in the preferences.")
                url.openInDefaultBrowser()
            }
        } else {
            url.openInDefaultBrowser()
        }
    case .zoom:
        if Defaults[.useAppForZoomLinks] {
            let urlString = url.absoluteString.replacingOccurrences(of: "?", with: "&").replacingOccurrences(of: "/j/", with: "/join?confno=")
            var zoomAppUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomAppUrl.scheme = "zoommtg"
            let result = zoomAppUrl.url!.openInDefaultBrowser()
            if !result {
                sendNotification("Oops! Unable to open the link in Zoom app", "Make sure you have Zoom app installed, or change the app in the preferences.")
                url.openInDefaultBrowser()
            }
        } else {
            url.openInDefaultBrowser()
        }
    case .zoom_native:
        let result = url.openInDefaultBrowser()
        if !result {
            sendNotification("Oops! Unable to open the native link in Zoom app", "Make sure you have Zoom app installed, or change the app in the preferences.")

            let urlString = url.absoluteString.replacingFirstOccurrence(of: "&", with: "?").replacingOccurrences(of: "/join?confno=", with: "/j/")
            var zoomBrowserUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomBrowserUrl.scheme = "https"
            zoomBrowserUrl.url!.openInDefaultBrowser()
        }
    case .facetime:
        NSWorkspace.shared.open(URL(string: "facetime://" + url.absoluteString)!)
    case .facetimeaudio:
        NSWorkspace.shared.open(URL(string: "facetime-audio://" + url.absoluteString)!)
    case .phone:
        NSWorkspace.shared.open(URL(string: "tel://" + url.absoluteString)!)
    default:
        url.openInDefaultBrowser()
    }
}

func removePatchVerion(_ version: String) -> String {
    let versionArray = version.split(separator: ".")
    let major = versionArray[0]
    let minor = versionArray[1]
    return "\(major).\(minor)"
}
