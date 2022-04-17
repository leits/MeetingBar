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

            NSWorkspace.shared.open([self], withApplicationAt: URL(fileURLWithPath: browserPath), configuration: configuration) { app, error in
                guard app != nil else {
                    NSLog("Can't open \(self) in \(browserName): \(String(describing: error?.localizedDescription))")
                    sendNotification("link_url_cant_open_title".loco(browserName), "link_url_cant_open_message".loco(browserName))
                    self.openInDefaultBrowser()
                    return
                }
                NSLog("Opening \(self) in \(browserName)")
            }
        }
    }

    @discardableResult
    func openInDefaultBrowser() -> Bool {
        let result = NSWorkspace.shared.open(self)
        if result {
            NSLog("Opening \(self) in default browser")
        } else {
            sendNotification("link_url_cant_open_title".loco("preferences_services_link_default_browser_value".loco()), "preferences_services_create_meeting_custom_url_placeholder".loco())
        }
        return result
    }
}
