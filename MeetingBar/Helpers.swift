//
//  Helpers.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import Cocoa

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
    NSWorkspace.shared.open([link], withApplicationAt: chromeUrl, configuration: configuration, completionHandler: {
        app, error in
        if app != nil {
            NSLog("Open \(link) in Chrome")
        } else {
            NSLog("Can't open \(link) in Chrome: \(String(describing: error?.localizedDescription))")
            sendNotification("Can't open link in Chrome", "Check browser or change settings")
            _ = openLinkInDefaultBrowser(link)
        }
        })
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
        title = "Event with long title may not be displayed in your status bar"
        let index = title.index(title.startIndex, offsetBy: offset, limitedBy: title.endIndex)
        title = String(title[...(index ?? title.endIndex)])
        if offset < Int(TitleLengthLimits.max) {
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
