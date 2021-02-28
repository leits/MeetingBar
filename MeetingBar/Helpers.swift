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

  struct MeetingLink: Equatable {
    let service: MeetingServices?
    let url: URL
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

    var links = outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    if !links.isEmpty {
        repeat {
            let urlRange = links[0].range( at: 1)
            let safeLinks = links.map { String(text[Range($0.range, in: text)!]) }
            if !safeLinks.isEmpty {
                let serviceUrl = (text as NSString).substring(with: urlRange)
                NSLog("Found service url \(serviceUrl)")
                text = text.replacingOccurrences(of: safeLinks[0], with: serviceUrl.decodeUrl()!)
            }
            links = outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        } while !links.isEmpty
    }

    NSLog("Returning text \(text)")
    return text
}

func getMatch(text: String, regex: NSRegularExpression) -> String? {
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range, in: text)!]) }

    if !resultsMap.isEmpty {
        let meetLink = resultsMap[0]
        return meetLink
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

func generateTitleSample(_ titleFormat: EventTitleFormat, _ offset: Int) -> String {
    var title: String
    switch titleFormat {
    case .show:
        title = "An event with an excessively sizeable 55-character title"
        title = title.truncated(to: offset)
        title += " in 1h 25m"
    case .dot:
        title = "• in 1h 25m"
    case .none:
        title = ""
    }

    return title
}

func generateTitleIconSample(_ titleIconFormat: EventTitleIconFormat) -> NSImage {
    let image: NSImage
    if titleIconFormat == EventTitleIconFormat.eventtype {
        image = NSImage(named: "ms_teams_icon")!
    } else {
        image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
    }
    image.size = NSSize(width: 16, height: 16)
    return image
}

func generateTitleSample(_ offset: Int) -> String {
    let title = "An event with an excessively sizeable 100-character title to show the shorten capabilities here ...."
    return title.truncated(to: offset)
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
    let regex = GoogleRegex.emailAddress
    let text = event.calendar.source.description
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range(at: 1), in: text)!]) }
    if !resultsMap.isEmpty {
        return resultsMap.first
    }
    return nil
}

func emailMe() {
    Links.emailMe.openInDefaultBrowser()
}

/**
 * this method will collect text from the location, url and notes field of an event and try to find a known meeting url link.
 * As meeting links can be part of a outlook safe url, we will extract the original link from outlook safe links.
 */
func getMeetingLink(_ event: EKEvent) -> MeetingLink? {
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
                if var link = getMatch(text: field, regex: regex) {
                    if service == .meet,
                       let account = getGmailAccount(event),
                       let urlEncodedAccount = account.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        link += "?authuser=\(urlEncodedAccount)"
                    }
                    if let url = URL(string: link) {
                        return MeetingLink(service: service, url: url)
                    }
                }
            }
        }
    }
    return nil
}
