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
        _, _ in
        NSLog("Open \(link) in Chrome")
        })
}

func openLinkInDefaultBrowser(_ link: URL) {
    NSWorkspace.shared.open(link)
    NSLog("Open \(link) in default browser")
}

func cleanUpNotes(_ notes: String) -> String {
    let zoomSeparator = "\n──────────"
    let teamsSeparator = "\n──────────"
    let meetSeparator = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
    let cleanNotes = notes.components(separatedBy: zoomSeparator)[0].components(separatedBy: teamsSeparator)[0].components(separatedBy: meetSeparator)[0]
    return cleanNotes
}

func generateTitleSample(_ titleFormat: EventTitleFormat, _ etaFormat: ETAFormat, _ offset: Int) -> String {
    var title: String
    switch titleFormat {
    case .hide:
        title = "Meeting"
    case .show:
        title = "Long title which may not be displayed in your status bar"
        let index = title.index(title.startIndex, offsetBy: offset, limitedBy: title.endIndex)
        title = String(title[...(index ?? title.endIndex)])
        if offset < Int(TitleLengthLimits.max) {
            title += "..."
        }
    case .dot:
        title = "•"
    }
    
    var eta: String
    switch etaFormat {
    case .full:
        eta = "1 hour 25 minutes"
    case .short:
        eta = "1 hr 25 min"
    case .abbreviated:
        eta = "1h 25m"
    }

    return "\(title) in \(eta)"
}
