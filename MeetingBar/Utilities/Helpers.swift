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
import Foundation

struct Bookmark: Codable, Defaults.Serializable, Hashable {
    var name: String
    /// Provider string ID (= MeetingServices.rawValue for built-in providers).
    /// Backward-compatible: the old Bookmark.service (MeetingServices) encoded
    /// its rawValue as the JSON string, so existing stored bookmarks decode fine.
    var service: String
    var url: URL
}

struct ProcessedEvent: Codable, Defaults.Serializable, Hashable {
    var id: String
    var lastModifiedDate: Date?
    var eventEndDate: Date
}

func cleanUpNotes(_ notes: String) -> String {
    let zoomSeparator = "\n──────────"
    let meetSeparator =
        "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
    let cleanNotes =
        notes
        .components(separatedBy: zoomSeparator)[0]
        .components(separatedBy: meetSeparator)[0]
        .htmlTagsStripped()
    return cleanNotes
}

func compareVersions(_ versionX: String, _ versionY: String) -> Bool {
    versionX.compare(versionY, options: .numeric) == .orderedDescending
}

func addInstalledBrowser() {
    let existingBrowsers = Defaults[.browsers]

    var appUrls =
        LSCopyApplicationURLsForURL(URL(string: "https:")! as CFURL, .all)?.takeRetainedValue()
        as? [URL]

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

@MainActor func createNSViewFromText(
    text: String,
    font: NSFont = NSFont.systemFont(ofSize: 14),
    maxWidth: CGFloat = 300.0
) -> NSView {
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
                NSAttributedString.Key.font: font
            ],
            maxWidth: maxWidth
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
            paddingView.frame = NSRect(
                x: 0.0, y: 0.0, width: frame.width + 20, height: frame.height)
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

func getInstallationDate() -> Date? {
    let urlToDocumentsFolder: URL? = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask
    ).last
    return try? FileManager.default.attributesOfItem(atPath: (urlToDocumentsFolder?.path)!)[
        .creationDate] as? Date
}

/*
 * -----------------------
 * MARK: - Fantastical
 * ------------------------
 */

func checkIsFantasticalInstalled() -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.flexibits.fantastical2.mac")
        != nil
}

func openInFantastical(startDate: Date, title: String) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let queryItems = [
        URLQueryItem(name: "date", value: dateFormatter.string(from: startDate)),
        URLQueryItem(name: "title", value: title)
    ]
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

func openLinkFromClipboard() {
    let pasteboard = NSPasteboard.general
    let clipboardContent = pasteboard.string(forType: .string) ?? ""

    if !clipboardContent.isEmpty {
        let meetingLink = detectMeetingLink(
            clipboardContent, customRegexes: Defaults[.customRegexes])

        if let meetingLink = meetingLink {
            MeetingOpener.open(meetingLink: meetingLink)
        } else {
            let validUrl = NSURL(string: clipboardContent)
            if validUrl != nil {
                URL(string: clipboardContent)?.openInDefaultBrowser()
            } else {
                sendNotification(
                    "No valid url",
                    "Clipboard has no meeting link, so the meeting cannot be started")
            }
        }
    } else {
        sendNotification(
            "Clipboard is empty",
            "Clipboard has no content, so the meeting cannot be started...")
    }
}

func generateFakeEvent() -> MBEvent {
    let calendar = MBCalendar(
        title: "Fake calendar", id: "fake_cal", source: nil, email: nil, color: .black)

    let event = MBEvent(
        id: "test_event",
        lastModifiedDate: nil,
        title: "Test event",
        status: .confirmed,
        notes: nil,
        location: nil,
        url: URL(string: "https://zoom.us/j/5551112222")!,
        organizer: nil,
        startDate: Calendar.current.date(byAdding: .minute, value: 3, to: Date())!,
        endDate: Calendar.current.date(byAdding: .minute, value: 33, to: Date())!,
        isAllDay: false,
        recurrent: false,
        calendar: calendar
    )
    return event
}

extension Data {
    init?(base64URL urlString: String) {
        var st = urlString.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - st.count % 4
        if pad < 4 { st.append(String(repeating: "=", count: pad)) }
        self.init(base64Encoded: st)
    }
}

extension NSImage {
    /// Returns a copy tinted with macOS disabled text colour.
    func tintedDisabled() -> NSImage {
        let copy = self.copy() as! NSImage
        copy.lockFocus()
        NSColor.disabledControlTextColor
            .withAlphaComponent(0.4)
            .set()
        let rect = NSRect(origin: .zero, size: copy.size)
        rect.fill(using: .sourceAtop)  // keep alpha, replace colour

        copy.unlockFocus()
        return copy
    }
}
