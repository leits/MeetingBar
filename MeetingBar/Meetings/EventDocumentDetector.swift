//
//  EventDocumentDetector.swift
//  MeetingBar
//
//  Pure extraction of invite documents/attachments (#917): Google Calendar
//  attachment metadata plus document links found in an invite's notes,
//  location or URL. Conference links (anything the meeting-link detector
//  recognises, plus Google Meet dial-in/help boilerplate) are excluded so they
//  stay in the Join actions. Nothing here fetches remote content: titles come
//  from the invite itself or are derived from the URL.
//

import Foundation

/// What kind of document a link points at. Drives the menu icon and the
/// fallback title when the invite gives no meaningful one.
public enum EventDocumentKind: String, Sendable, CaseIterable {
    case googleDocs
    case googleSheets
    case googleSlides
    case googleForms
    case googleDrive
    case pdf
    case word
    case excel
    case powerPoint
    case oneDrive
    case figma
    case notion
    case confluence
    case jira
    case miro
    case github
    case dropbox
    case link

    /// Human-readable type name used as the fallback title.
    var displayName: String? {
        switch self {
        case .googleDocs: return "Google Docs"
        case .googleSheets: return "Google Sheets"
        case .googleSlides: return "Google Slides"
        case .googleForms: return "Google Forms"
        case .googleDrive: return "Google Drive"
        case .pdf: return "PDF"
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerPoint: return "PowerPoint"
        case .oneDrive: return "OneDrive"
        case .figma: return "Figma"
        case .notion: return "Notion"
        case .confluence: return "Confluence"
        case .jira: return "Jira"
        case .miro: return "Miro"
        case .github: return "GitHub"
        case .dropbox: return "Dropbox"
        case .link: return nil
        }
    }

    /// SF Symbol used when no site icon is available.
    public var symbolName: String {
        switch self {
        case .googleDocs, .word: return "doc.text"
        case .googleSheets, .excel: return "tablecells"
        case .googleSlides, .powerPoint: return "rectangle.on.rectangle"
        case .googleForms: return "list.bullet.rectangle"
        case .googleDrive, .oneDrive, .dropbox: return "folder"
        case .pdf: return "doc.richtext"
        case .figma: return "paintpalette"
        case .notion: return "note.text"
        case .confluence: return "book"
        case .jira: return "checklist"
        case .miro: return "square.on.square"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        }
    }
}

/// One document/attachment attached to or linked from an invite.
public struct EventDocument: Hashable, Sendable {
    public let url: URL
    public let title: String
    public let kind: EventDocumentKind
    /// `true` when `title` came from the invite (attachment title or link
    /// text) rather than being derived from the URL.
    public let hasProvidedTitle: Bool
    /// Icon published by the provider for this file (Drive `iconLink`).
    public var iconURL: URL?

    /// Stable identity used to merge copies of the same document.
    var dedupKey: String { EventDocumentDetector.dedupKey(for: url) }

    /// Google Docs/Drive file id, when the link points at one. Lets the
    /// Google provider look up the file's real name via Drive metadata.
    public var googleFileID: String? { EventDocumentDetector.googleFileID(for: url) }

    /// Copy with a title (and icon) resolved from provider metadata.
    public func resolved(title: String, iconURL: URL?) -> EventDocument {
        var copy = EventDocument(url: url, title: title, kind: kind, hasProvidedTitle: true)
        copy.iconURL = iconURL ?? self.iconURL
        return copy
    }
}

/// Structured attachment metadata from a provider (Google `attachments[]`).
public struct EventAttachmentInput: Sendable {
    public let url: URL
    public let title: String?
    public let mimeType: String?

    public init(url: URL, title: String?, mimeType: String?) {
        self.url = url
        self.title = title
        self.mimeType = mimeType
    }
}

public enum EventDocumentDetector {
    /// Extracts deduplicated documents, structured attachments first, then
    /// links in appearance order across notes, location and the event URL.
    public static func documents(
        attachments: [EventAttachmentInput] = [],
        notes: String?,
        location: String?,
        eventURL: URL?,
        excludedURLs: [URL] = []
    ) -> [EventDocument] {
        var found: [EventDocument] = attachments.compactMap { attachment in
            let kind = kind(for: attachment.url, mimeType: attachment.mimeType)
            return makeDocument(url: attachment.url, providedTitle: attachment.title, kind: kind)
        }
        for text in [notes, location, eventURL?.absoluteString].compactMap({ $0 }) {
            found.append(contentsOf: links(in: text).compactMap { link in
                makeDocument(url: link.url, providedTitle: link.text, kind: nil)
            })
        }
        let excludedKeys = Set(excludedURLs.map(dedupKey(for:)))
        return merged(found.filter { !excludedKeys.contains($0.dedupKey) })
    }

    /// Deduplicates by normalised URL, keeping first-seen order and preferring
    /// a copy whose title came from the invite. Used both within one event and
    /// when merging copies of the same event from different calendars.
    public static func merged(_ documents: [EventDocument]) -> [EventDocument] {
        var order: [String] = []
        var byKey: [String: EventDocument] = [:]
        for document in documents {
            let key = document.dedupKey
            if let existing = byKey[key] {
                if !existing.hasProvidedTitle, document.hasProvidedTitle {
                    var upgraded = document
                    upgraded.iconURL = document.iconURL ?? existing.iconURL
                    byKey[key] = upgraded
                } else if existing.iconURL == nil, let iconURL = document.iconURL {
                    byKey[key]?.iconURL = iconURL
                }
            } else {
                order.append(key)
                byKey[key] = document
            }
        }
        return order.compactMap { byKey[$0] }
    }

    // MARK: - Link extraction

    private struct FoundLink {
        let url: URL
        let text: String?
    }

    private static let anchorRegex = try! NSRegularExpression(
        pattern: #"(?is)<a\b[^>]*?\bhref\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a\s*>"#
    )
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func links(in rawText: String) -> [FoundLink] {
        let text = cleanupMeetingRedirects(rawText: rawText)
        var result: [FoundLink] = []
        var remainder = text

        // 1. HTML anchors carry the organiser's chosen link text as a title.
        let range = NSRange(text.startIndex..., in: text)
        for match in anchorRegex.matches(in: text, range: range) {
            guard let hrefRange = Range(match.range(at: 1), in: text),
                  let textRange = Range(match.range(at: 2), in: text) else { continue }
            let href = HTMLPlainText.from(String(text[hrefRange]))
            guard let url = URL(string: href) else { continue }
            let linkText = HTMLPlainText.from(String(text[textRange]))
            result.append(FoundLink(url: url, text: linkText))
        }
        if !result.isEmpty {
            remainder = anchorRegex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        }

        // 2. Bare URLs in the remaining (plain) text.
        let plain = HTMLPlainText.from(remainder)
        if let linkDetector {
            let plainRange = NSRange(plain.startIndex..., in: plain)
            for match in linkDetector.matches(in: plain, range: plainRange) {
                if let url = match.url { result.append(FoundLink(url: url, text: nil)) }
            }
        }
        return result
    }

    // MARK: - Building a document

    private static func makeDocument(url rawURL: URL, providedTitle: String?, kind explicitKind: EventDocumentKind?) -> EventDocument? {
        let url = unwrapped(rawURL)
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), !host.isEmpty,
              !isConferenceLink(url) else { return nil }

        let kind = explicitKind ?? kind(for: url, mimeType: nil)
        let trimmedTitle = providedTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let isMeaningful = trimmedTitle.map { isMeaningfulTitle($0, for: url) } ?? false
        let title = isMeaningful ? trimmedTitle! : fallbackTitle(for: url, kind: kind, host: host)
        return EventDocument(url: url, title: title, kind: kind, hasProvidedTitle: isMeaningful)
    }

    private static func unwrapped(_ url: URL) -> URL {
        let cleaned = cleanupMeetingRedirects(rawText: url.absoluteString)
        return URL(string: cleaned) ?? url
    }

    /// A title is meaningful unless it is empty or just the URL/host again.
    private static func isMeaningfulTitle(_ title: String, for url: URL) -> Bool {
        guard !title.isEmpty else { return false }
        let lowered = title.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("www.") {
            return false
        }
        if let host = url.host?.lowercased(), lowered == host || lowered == host.replacingOccurrences(of: "www.", with: "") {
            return false
        }
        return true
    }

    /// "Google Docs", "Figma", … for known types; otherwise a brand-like name
    /// from the domain (`google.com` → "Google", `wiki.acme.co.uk` → "Acme").
    static func fallbackTitle(for url: URL, kind: EventDocumentKind, host: String) -> String {
        if let name = kind.displayName { return name }
        return siteName(forHost: host)
    }

    static func siteName(forHost host: String) -> String {
        var labels = host.lowercased().split(separator: ".").map(String.init)
        if labels.first == "www" { labels.removeFirst() }
        guard labels.count >= 2 else { return host.capitalized }
        // Treat common two-part public suffixes (co.uk, com.au, …) as one TLD.
        let secondLevel = labels[labels.count - 2]
        let compoundSuffixes: Set<String> = ["co", "com", "org", "net", "gov", "ac", "edu"]
        let nameIndex = (labels.count >= 3 && compoundSuffixes.contains(secondLevel) && labels.last!.count == 2)
            ? labels.count - 3
            : labels.count - 2
        let name = labels[nameIndex]
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: - Classification

    static func kind(for url: URL, mimeType: String?) -> EventDocumentKind {
        if let mimeType = mimeType?.lowercased() {
            switch mimeType {
            case "application/vnd.google-apps.document": return .googleDocs
            case "application/vnd.google-apps.spreadsheet": return .googleSheets
            case "application/vnd.google-apps.presentation": return .googleSlides
            case "application/vnd.google-apps.form": return .googleForms
            case "application/pdf": return .pdf
            default: break
            }
            if mimeType.contains("wordprocessingml") || mimeType == "application/msword" { return .word }
            if mimeType.contains("spreadsheetml") || mimeType == "application/vnd.ms-excel" { return .excel }
            if mimeType.contains("presentationml") || mimeType == "application/vnd.ms-powerpoint" { return .powerPoint }
        }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host == "docs.google.com" {
            if path.hasPrefix("/document") { return .googleDocs }
            if path.hasPrefix("/spreadsheets") { return .googleSheets }
            if path.hasPrefix("/presentation") { return .googleSlides }
            if path.hasPrefix("/forms") { return .googleForms }
            return .googleDrive
        }
        if host == "drive.google.com" { return .googleDrive }
        if path.hasSuffix(".pdf") { return .pdf }
        if path.hasSuffix(".docx") || path.hasSuffix(".doc") { return .word }
        if path.hasSuffix(".xlsx") || path.hasSuffix(".xls") { return .excel }
        if path.hasSuffix(".pptx") || path.hasSuffix(".ppt") { return .powerPoint }
        if host.hasSuffix("sharepoint.com") || host == "onedrive.live.com" || host == "1drv.ms" { return .oneDrive }
        if host.hasSuffix("figma.com") { return .figma }
        if host.hasSuffix("notion.so") || host.hasSuffix("notion.site") { return .notion }
        if host.hasSuffix("atlassian.net") {
            if path.hasPrefix("/wiki") { return .confluence }
            if path.hasPrefix("/browse") || path.hasPrefix("/jira") { return .jira }
        }
        if host.hasSuffix("miro.com") { return .miro }
        if host == "github.com" || host.hasSuffix(".github.com") { return .github }
        if host.hasSuffix("dropbox.com") { return .dropbox }
        return .link
    }

    /// Meeting links stay in Join actions; Google Meet dial-in, PIN and help
    /// boilerplate and links back into the calendar itself are not documents.
    static func isConferenceLink(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host == "meet.google.com" || host == "tel.meet" || host.hasSuffix(".meet.google.com") { return true }
        if host == "g.co", path.hasPrefix("/meet") { return true }
        if host == "support.google.com", path.contains("/meet") || url.absoluteString.contains("/a/users/answer/9282720") {
            return true
        }
        if host == "calendar.google.com" || host == "accounts.google.com" { return true }
        if host.hasSuffix("google.com"), path.hasPrefix("/calendar") { return true }
        return detectMeetingLink(url.absoluteString) != nil
    }

    // MARK: - Dedup

    /// Normalises a URL so cosmetic variants of the same document collapse:
    /// scheme/host case, `www.`, fragments, trailing slashes and, for Google
    /// Docs/Drive, everything after the file id (`/edit?usp=sharing`, …).
    static func dedupKey(for url: URL) -> String {
        let url = unwrapped(url)
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path

        if host == "docs.google.com" || host == "drive.google.com" {
            if let fileID = googleFileID(path: path, query: url.query) {
                return "google:\(fileID)"
            }
        }

        var key = host + path
        while key.hasSuffix("/") { key.removeLast() }
        if let query = url.query, !query.isEmpty { key += "?" + query }
        return key
    }

    static func googleFileID(for url: URL) -> String? {
        let url = unwrapped(url)
        let host = url.host?.lowercased() ?? ""
        guard host == "docs.google.com" || host == "drive.google.com" else { return nil }
        return googleFileID(path: url.path, query: url.query)
    }

    private static func googleFileID(path: String, query: String?) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(of: "d"), index + 1 < parts.count {
            return parts[index + 1]
        }
        if let query,
           let id = URLComponents(string: "x:?\(query)")?.queryItems?.first(where: { $0.name == "id" })?.value {
            return id
        }
        return nil
    }
}
