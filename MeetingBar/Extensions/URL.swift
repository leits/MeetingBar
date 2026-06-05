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

            if browserPath.hasSuffix(".app") {
                NSWorkspace.shared.open([self], withApplicationAt: URL(fileURLWithPath: browserPath), configuration: configuration) { app, _ in
                    guard app != nil else {
                        AppMessageCenter.shared.post(.browserUnavailable(name: browserName))
                        self.openInDefaultBrowser()
                        return
                    }
                }
            } else {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: browserPath)
                process.arguments = [self.absoluteString]

                do {
                    try process.run()
                } catch {
                    AppMessageCenter.shared.post(.browserUnavailable(name: browserName))
                    openInDefaultBrowser()
                }
                return
            }

        }
    }

    @discardableResult
    func openInDefaultBrowser() -> Bool {
        let result = NSWorkspace.shared.open(self)
        if !result {
            AppMessageCenter.shared.post(.defaultBrowserUnavailable)
        }
        return result
    }
}
