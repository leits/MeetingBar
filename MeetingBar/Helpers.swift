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


func getMatch(text: String, regex: NSRegularExpression) -> String? {
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range, in: text)!]) }
    if !resultsMap.isEmpty {
        let meetLink = resultsMap[0]
        return meetLink
    }
    return nil
}

func openLinkInChrome(_ link: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    let chromeUrl = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    NSWorkspace.shared.open([link], withApplicationAt: chromeUrl, configuration: configuration) { app, error in
        if app != nil {
            NSLog("Open \(link) in Chrome")
        } else {
            NSLog("Can't open \(link) in Chrome: \(String(describing: error?.localizedDescription))")
            sendNotification("Oops! Unable to open the link in Chrome", "Make sure you have Chrome installed, or change the browser in the preferences.")
            _ = openLinkInDefaultBrowser(link)
        }
    }
}

func openLinkInDefaultBrowser(_ link: URL) -> Bool {
    let result = NSWorkspace.shared.open(link)
    if result {
        NSLog("Open \(link) in default browser")
    } else {
        NSLog("Can't open \(link) in default browser")
    }
    return result
}

func cleanUpNotes(_ notes: String) -> String {
    let zoomSeparator = "\n──────────"
    let meetSeparator = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
    let cleanNotes = notes.components(separatedBy: zoomSeparator)[0].components(separatedBy: meetSeparator)[0]
    return cleanNotes
}

func generateTitleSample(_ titleFormat: EventTitleFormat, _ offset: Int) -> String {
    var title: String
    switch titleFormat {
    case .show:
        title = "An event with an excessively sizeable 55-character title"
        let index = title.index(title.startIndex, offsetBy: offset - 1, limitedBy: title.endIndex)
        title = String(title[...(index ?? title.endIndex)])
                .trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
        if offset < (title.count - 1) {
            title += "..."
        }
    case .dot:
        title = "•"
    }
    return "\(title) in 1h 25m"
}

func getRegexForService(_ service: MeetingServices) -> NSRegularExpression? {
    let regexes = LinksRegex()
    let mirror = Mirror(reflecting: regexes)

    for child in mirror.children {
        if child.label == String(describing: service) {
            return (child.value as! NSRegularExpression)
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
    _ = openLinkInDefaultBrowser(Links.emailMe)
}

func getMeetingLink(_ event: EKEvent) -> (service: MeetingServices?, url: URL)? {
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

    for field in linkFields {
        for pattern in Defaults[.customRegexes] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                if let link = getMatch(text: field, regex: regex) {
                    if let url = URL(string: link) {
                        return (nil, url)
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
                        return (service, url)
                    }
                }
            }
        }
    }
    return nil
}
