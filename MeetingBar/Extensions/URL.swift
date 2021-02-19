//
//  URL.swift
//  MeetingBar
//
//  Created by 0bmxa on 2021-02-05.
//  Copyright © 2021 MeetingBar. All rights reserved.
//

import AppKit

extension URL {
    func openIn(browser: Browser) {
        guard let browserURL = browser.url else {
            self.openInDefaultBrowser()
            return
        }
        let browserName = browser.rawValue

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([self], withApplicationAt: browserURL, configuration: configuration) { app, error in
            guard app != nil else {
                NSLog("Can't open \(self) in \(browserName): \(String(describing: error?.localizedDescription))")
                sendNotification("Oops! Unable to open the link in \(browserName)", "Make sure you have \(browserName) installed, or change the browser in preferences.")
                self.openInDefaultBrowser()
                return
            }
            NSLog("Opening \(self) in \(browserName)")
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
