//
//  Helpers.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import AppKit
import Cocoa
import Defaults
import EventKit

struct Bookmark: Encodable, Decodable, Hashable {
    var name: String
    var service: MeetingServices
    var url: URL
}

struct ProcessedEvent: Encodable, Decodable, Hashable {
    var id: String
    var lastModifiedDate: Date
    var eventEndDate: Date
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
func cleanupOutlookSafeLinks(rawText: String) -> String {
    var text = rawText
    var links = UtilsRegex.outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    if !links.isEmpty {
        repeat {
            let urlRange = links[0].range(at: 1)
            let safeLinks = links.map { String(text[Range($0.range, in: text)!]) }
            if !safeLinks.isEmpty {
                let serviceUrl = (text as NSString).substring(with: urlRange)
                text = text.replacingOccurrences(of: safeLinks[0], with: serviceUrl.decodeUrl()!)
            }
            links = UtilsRegex.outlookSafeLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        } while !links.isEmpty
    }
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

func getEmailAccount(_ source: String?) -> String? {
    // Hacky and likely to break, but should work until Apple changes something
    if let text = source {
        return getMatch(text: text, regex: UtilsRegex.emailAddress)
    }
    return nil
}

func compareVersions(_ version_x: String, _ version_y: String) -> Bool {
    version_x.compare(version_y, options: .numeric) == .orderedDescending
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

func addInstalledBrowser() {
    let existingBrowsers = Defaults[.browsers]

    var appUrls = LSCopyApplicationURLsForURL(URL(string: "https:")! as CFURL, .all)?.takeRetainedValue() as? [URL]

    if !appUrls!.isEmpty {
        appUrls = appUrls?.sorted { $0.path.fileName() < $1.path.fileName() }
        appUrls?.forEach {
            let browser = Browser(name: $0.path.fileName(), path: $0.path)
            if !existingBrowsers.contains(where: { $0.name == browser.path.fileName() }) {
                Defaults[.browsers].append(browser)
            }
        }
    }
}

func hexStringToUIColor(hex: String) -> NSColor {
    var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    if cString.hasPrefix("#") {
        cString.remove(at: cString.startIndex)
    }

    if (cString.count) != 6 {
        return NSColor.gray
    }

    var rgbValue: UInt64 = 0
    Scanner(string: cString).scanHexInt64(&rgbValue)

    return NSColor(
        red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
        alpha: CGFloat(1.0)
    )
}

func createNSViewFromText(text: String) -> NSView {
    // Create views
    let paddingView = NSView()
    let textView = NSTextView()
    paddingView.addSubview(textView)

    // Text styling
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = NSLineBreakMode.byWordWrapping
    textView.textStorage?.setAttributedString(
        text.splitWithNewLineAttributedString(
            with: [
                NSAttributedString.Key.paragraphStyle: paragraphStyle,
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: 14),
            ],
            maxWidth: 300.0
        )
        .withLinksEnabled()
    )
    textView.backgroundColor = .clear
    textView.textColor = .textColor

    // Adjust frame layout for padding
    if let textContainer = textView.textContainer {
        textView.layoutManager?.ensureLayout(for: textContainer)
        if let frame = textView.layoutManager?.usedRect(for: textContainer) {
            // There's 10pt of padding seemingly built into the left side,
            // no such thing on the right so we go 20pt to match the left side
            textView.frame = NSRect(x: 10.0, y: 0.0, width: frame.width, height: frame.height)
            paddingView.frame = NSRect(x: 0.0, y: 0.0, width: frame.width + 20, height: frame.height)
        } else {
            // Backup layout if we couldn't calculate frame
            textView.autoresizingMask = [.width, .height]
        }
    } else {
        // Backup layout if we couldn't calculate frame
        textView.autoresizingMask = [.width, .height]
    }
    return paddingView
}

/*
 * -----------------------
 * MARK: - Fantastical
 * ------------------------
 */

func checkIsFantasticalInstalled() -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.flexibits.fantastical2.mac") != nil
}

func openInFantastical(startDate: Date, title: String) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let queryItems = [URLQueryItem(name: "date", value: dateFormatter.string(from: startDate)), URLQueryItem(name: "title", value: title)]
    var fantasticalUrlComp = URLComponents()
    fantasticalUrlComp.scheme = "x-fantastical3"
    fantasticalUrlComp.host = "show"
    fantasticalUrlComp.queryItems = queryItems

    let fantasticalUrl = fantasticalUrlComp.url!
    fantasticalUrl.openInDefaultBrowser()
}

/*
 * -----------------------
 * MARK: - Clipboard
 * ------------------------
 */

func getClipboardContent() -> String {
    let pasteboard = NSPasteboard.general
    return pasteboard.string(forType: .string) ?? ""
}

func openLinkFromClipboard() {
    let clipboardContent = getClipboardContent()

    if !clipboardContent.isEmpty {
        let meetingLink = detectMeetingLink(clipboardContent)

        if let meetingLink = meetingLink {
            openMeetingURL(meetingLink.service, meetingLink.url, nil)
        } else {
            let validUrl = NSURL(string: clipboardContent)
            if validUrl != nil {
                URL(string: clipboardContent)?.openInDefaultBrowser()
            } else {
                sendNotification("No valid url",
                                 "Clipboard has no meeting link, so the meeting cannot be started")
            }
        }
    } else {
        sendNotification("Clipboard is empty",
                         "Clipboard has no content, so the meeting cannot be started...")
    }
}
