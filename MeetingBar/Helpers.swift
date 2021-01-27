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

struct Bookmark: Encodable, Decodable, Hashable {
    var name: String
    var service: MeetingServices
    var url: String
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

func openLinkInChrome(_ link: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    let chromeUrl = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    NSWorkspace.shared.open([link], withApplicationAt: chromeUrl, configuration: configuration) { app, error in
        if app != nil {
            NSLog("Open \(link) in Chrome")
        } else {
            NSLog("Can't open \(link) in Chrome: \(String(describing: error?.localizedDescription))")
            sendNotification(title: "Oops! Unable to open the link in Chrome", text: "Make sure you have Chrome installed, or change the browser in the preferences.")
            _ = openLinkInDefaultBrowser(link)
        }
    }
}

func openLinkInChromium(_ link: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    let chromiumUrl = URL(fileURLWithPath: "/Applications/Chromium.app")
    NSWorkspace.shared.open([link], withApplicationAt: chromiumUrl, configuration: configuration) { app, error in
        if app != nil {
            NSLog("Open \(link) in Chromium")
        } else {
            NSLog("Can't open \(link) in Chromium: \(String(describing: error?.localizedDescription))")
            sendNotification(title: "Oops! Unable to open the link in Chromium", text: "Make sure you have Chromium installed, or change the browser in the preferences.")
            _ = openLinkInDefaultBrowser(link)
        }
    }
}

func openLinkInFirefox(_ link: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    let firefoxUrl = URL(fileURLWithPath: "/Applications/Firefox.app")
    NSWorkspace.shared.open([link], withApplicationAt: firefoxUrl, configuration: configuration) { app, error in
        if app != nil {
            NSLog("Open \(link) in Firefox")
        } else {
            NSLog("Can't open \(link) in Firefox: \(String(describing: error?.localizedDescription))")
            sendNotification(title: "Oops! Unable to open the link in Firefox", text: "Make sure you have Firefox installed, or change the browser in the preferences.")
            _ = openLinkInDefaultBrowser(link)
        }
    }
}

func openLinkInEdge(_ link: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    let edgeUrl = URL(fileURLWithPath: "/Applications/Microsoft Edge.app")
    NSWorkspace.shared.open([link], withApplicationAt: edgeUrl, configuration: configuration) { app, error in
        if app != nil {
            NSLog("Open \(link) in Edge")
        } else {
            NSLog("Can't open \(link) in Edge: \(String(describing: error?.localizedDescription))")
            sendNotification(title: "Oops! Unable to open the link in Edge", text: "Make sure you have Edge installed, or change the browser in the preferences.")
            _ = openLinkInDefaultBrowser(link)
        }
    }
}

func openLinkInBrave(_ link: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    let braveUrl = URL(fileURLWithPath: "/Applications/Brave Browser.app")
    NSWorkspace.shared.open([link], withApplicationAt: braveUrl, configuration: configuration) { app, error in
        if app != nil {
            NSLog("Open \(link) in Brave")
        } else {
            NSLog("Can't open \(link) in Brave: \(String(describing: error?.localizedDescription))")
            sendNotification(title: "Oops! Unable to open the link in Brave", text: "Make sure you have Brave installed, or change the browser in the preferences.")
            _ = openLinkInDefaultBrowser(link)
        }
    }
}

func openLinkInVivaldi(_ link: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    let vivaldiUrl = URL(fileURLWithPath: "/Applications/Vivaldi.app")
    NSWorkspace.shared.open([link], withApplicationAt: vivaldiUrl, configuration: configuration) { app, error in
        if app != nil {
            NSLog("Open \(link) in Vivaldi")
        } else {
            NSLog("Can't open \(link) in Vivaldi: \(String(describing: error?.localizedDescription))")
            sendNotification(title: "Oops! Unable to open the link in Vivaldi", text: "Make sure you have Vivaldi installed, or change the browser in the preferences.")
            _ = openLinkInDefaultBrowser(link)
        }
    }
}

func openLinkInOpera(_ link: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    let operaUrl = URL(fileURLWithPath: "/Applications/Opera.app")
    NSWorkspace.shared.open([link], withApplicationAt: operaUrl, configuration: configuration) { app, error in
        if app != nil {
            NSLog("Open \(link) in Opera")
        } else {
            NSLog("Can't open \(link) in Opera: \(String(describing: error?.localizedDescription))")
            sendNotification(title: "Oops! Unable to open the link in Opera", text: "Make sure you have Opera installed, or change the browser in the preferences.")
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
        title = title.trunc(limit: offset)
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
    return title.trunc(limit: offset)
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
