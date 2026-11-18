//
//  DocumentIconProvider.swift
//  MeetingBar
//
//  Menu icons for invite documents (#917). Shows the site's own favicon when
//  it has been fetched, otherwise an SF Symbol for the document type. Only
//  the public `/favicon.ico` of the link's host is requested, through an
//  ephemeral cookie-less session; document contents are never fetched.
//

import AppKit

@MainActor
final class DocumentIconProvider {
    static let shared = DocumentIconProvider()

    private static let iconSize = NSSize(width: 16, height: 16)
    private var favicons: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    /// Menu items waiting for a favicon, refreshed in place when it arrives.
    private var waitingItems: [String: NSHashTable<NSMenuItem>] = [:]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    func applyIcon(for document: EventDocument, to item: NSMenuItem) {
        if let googleIcon = Self.googleFileIcon(for: document.kind) {
            Self.setIcon(googleIcon, on: item)
            return
        }
        Self.setIcon(Self.symbol(for: document.kind), on: item)
        guard let iconURL = Self.iconURL(for: document) else { return }
        let key = iconURL.absoluteString
        if let favicon = favicons[key] {
            Self.setIcon(favicon, on: item)
            return
        }
        guard !failed.contains(key) else { return }
        waitingItems[key, default: .weakObjects()].add(item)
        fetchIcon(key: key, url: iconURL)
    }

    /// Provider icon (Drive `iconLink`, requested at 32 px for Retina) when
    /// known, otherwise the site's `/favicon.ico`.
    private static func iconURL(for document: EventDocument) -> URL? {
        if let iconURL = document.iconURL {
            let hiDPI = iconURL.absoluteString.replacingOccurrences(of: "/16/type/", with: "/32/type/")
            return URL(string: hiDPI) ?? iconURL
        }
        guard let host = document.url.host?.lowercased() else { return nil }
        return URL(string: "https://\(host)/favicon.ico")
    }

    /// Page-shaped icon with a folded corner for Google files, drawn
    /// locally: Google's own icons are flat squares, and their sites'
    /// favicon is the Drive logo.
    static func googleFileIcon(for kind: EventDocumentKind) -> NSImage? {
        let color: NSColor
        switch kind {
        case .googleDocs: color = NSColor(srgbRed: 0.26, green: 0.52, blue: 0.96, alpha: 1)
        case .googleSheets: color = NSColor(srgbRed: 0.06, green: 0.62, blue: 0.35, alpha: 1)
        case .googleSlides: color = NSColor(srgbRed: 0.96, green: 0.71, blue: 0.0, alpha: 1)
        case .googleForms: color = NSColor(srgbRed: 0.40, green: 0.23, blue: 0.72, alpha: 1)
        default: return nil
        }
        let image = NSImage(size: iconSize, flipped: true) { _ in
            let fold: CGFloat = 4
            let page = NSBezierPath()
            page.move(to: NSPoint(x: 3, y: 1))
            page.line(to: NSPoint(x: 13 - fold, y: 1))
            page.line(to: NSPoint(x: 13, y: 1 + fold))
            page.line(to: NSPoint(x: 13, y: 15))
            page.line(to: NSPoint(x: 3, y: 15))
            page.close()
            color.setFill()
            page.fill()
            let corner = NSBezierPath()
            corner.move(to: NSPoint(x: 13 - fold, y: 1))
            corner.line(to: NSPoint(x: 13 - fold, y: 1 + fold))
            corner.line(to: NSPoint(x: 13, y: 1 + fold))
            corner.close()
            NSColor.white.withAlphaComponent(0.45).setFill()
            corner.fill()
            NSColor.white.setFill()
            switch kind {
            case .googleDocs:
                for (y, width) in [(7.0, 6.0), (9.0, 6.0), (11.0, 4.0)] {
                    NSRect(x: 5, y: y, width: width, height: 1).fill()
                }
            case .googleSheets:
                NSRect(x: 5, y: 7, width: 6, height: 5).frame(withWidth: 1)
                NSRect(x: 7.5, y: 7, width: 1, height: 5).fill()
                NSRect(x: 5, y: 9, width: 6, height: 1).fill()
            case .googleSlides:
                NSRect(x: 5, y: 7.5, width: 6, height: 4).frame(withWidth: 1)
            default:
                for y in [7.0, 9.0, 11.0] {
                    NSRect(x: 5, y: y, width: 1, height: 1).fill()
                    NSRect(x: 7, y: y, width: 4, height: 1).fill()
                }
            }
            return true
        }
        return image
    }

    private func fetchIcon(key: String, url: URL) {
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        session.dataTask(with: url) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let image = (200..<300).contains(status) ? data.flatMap(NSImage.init(data:)) : nil
            Task { @MainActor in
                self?.finishFetch(host: key, image: image)
            }
        }.resume()
    }

    private func finishFetch(host: String, image: NSImage?) {
        inFlight.remove(host)
        guard let image, image.isValid else {
            failed.insert(host)
            waitingItems[host] = nil
            return
        }
        image.size = Self.iconSize
        favicons[host] = image
        for item in waitingItems[host]?.allObjects ?? [] {
            Self.setIcon(image, on: item)
        }
        waitingItems[host] = nil
    }

    /// Draws the icon inline at the start of the title. `NSMenuItem.image`
    /// is not rendered in MeetingBar's status menu on current macOS (event
    /// rows' service icons are missing too), so this uses a text attachment,
    /// like the running-meeting indicator.
    private static func setIcon(_ image: NSImage?, on item: NSMenuItem) {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString()
        if let image {
            let attachment = NSTextAttachment()
            attachment.image = image
            // Centre the icon on the text's cap height.
            attachment.bounds = NSRect(
                x: 0,
                y: (font.capHeight - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "  "))
        }
        title.append(NSAttributedString(string: item.title))
        title.addAttribute(.font, value: font, range: NSRange(location: 0, length: title.length))
        item.attributedTitle = title
    }

    private static func symbol(for kind: EventDocumentKind) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [.secondaryLabelColor]))
        return NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.rawValue)?
            .withSymbolConfiguration(configuration)
    }
}
