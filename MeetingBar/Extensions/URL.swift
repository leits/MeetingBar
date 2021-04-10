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
            configuration.createsNewApplicationInstance = true

            NSWorkspace.shared.open([self], withApplicationAt: URL(fileURLWithPath: browserPath), configuration: configuration) { app, error in
                guard app != nil else {
                    NSLog("Can't open \(self) in \(browserName): \(String(describing: error?.localizedDescription))")
                    sendNotification("Oops! Unable to open the link in \(browserName)", "Make sure you have \(browserName) installed, or change the browser in preferences.")
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
            NSLog("Can't open \(self) in default browser")
        }
        return result
    }
}
