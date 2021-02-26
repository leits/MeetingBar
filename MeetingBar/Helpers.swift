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
import AppKit


struct Bookmark: Encodable, Decodable, Hashable {
    var name: String
    var service: MeetingServices
    var url: String
}

/**
 * defines a browser by using a browser name, a path to the application and arguments to run
 */
struct Browser: Encodable, Decodable, Hashable {
    var name: String
    var path: String
    var arguments: String = ""
    var deletable = true
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


func bundleIdentifier(forAppName appName: String) -> String? {
    let workspace = NSWorkspace.shared
    let appPath = workspace.fullPath(forApplication: appName)
    if let appPath = appPath {
        let appBundle = Bundle(path: appPath)
        return appBundle?.bundleIdentifier
    }
    return nil
}

/**
 * adds the default browsers for the browser dialog
 */
func addInstalledBrowser() {
    let existingBrowser = Defaults[.browser]

    let defaultBrowserPath = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://")!)
    var appUrls = LSCopyApplicationURLsForURL(URL(string: "https:")! as CFURL, .all)?.takeRetainedValue() as? [URL]

    if !appUrls!.isEmpty {
        appUrls = appUrls?.sorted { $0.path.fileName() < $1.path.fileName() }

        appUrls?.forEach {
            let bundleId = bundleIdentifier(forAppName: $0.path)

            let browser = Browser(name: $0.path.fileName(), path: $0.path)
            if !existingBrowser.contains { $0.name == browser.path.fileName() } {
                Defaults[.browser].append(browser)
            }
        }
    }
}
