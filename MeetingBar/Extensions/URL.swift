//
//  URL.swift
//  MeetingBar
//
//  Created by 0bmxa on 2021-02-05.
//  Copyright © 2021 MeetingBar. All rights reserved.
//

import AppKit

extension URL {
    /**
     * opens the url in the browser instance.
     */
    func openIn(browser: Browser) {
        let browserPath = browser.path
        let browserName = browser.name

        if browserPath.isEmpty {
            openInDefaultBrowser()
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = true

            guard browserPath.hasSuffix(".app") else {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: browserPath)
                process.arguments = [self.absoluteString]

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    sendNotification("link_url_cant_open_title".loco(browserName), "link_url_cant_open_message".loco(browserName))
                    openInDefaultBrowser()
                }
                return
            }

            NSWorkspace.shared.open([self], withApplicationAt: URL(fileURLWithPath: browserPath), configuration: configuration) { app, _ in
                guard app != nil else {
                    sendNotification("link_url_cant_open_title".loco(browserName), "link_url_cant_open_message".loco(browserName))
                    self.openInDefaultBrowser()
                    return
                }
            }
        }
    }

    @discardableResult
    func openInDefaultBrowser() -> Bool {
        let result = NSWorkspace.shared.open(self)
        if !result {
            sendNotification("link_url_cant_open_title".loco("preferences_services_link_default_browser_value".loco()), "preferences_services_create_meeting_custom_url_placeholder".loco())
        }
        return result
    }
}
