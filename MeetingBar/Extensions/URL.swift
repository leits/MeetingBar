//
//  URL.swift
//  MeetingBar
//
//  Created by 0bmxa on 2021-02-05.
//  Copyright © 2021 MeetingBar. All rights reserved.
//

import AppKit

extension URL {
    @discardableResult
    func shell(_ args: [String]) -> Int32 {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = args
        try? task.run()

        task.waitUntilExit()
        return task.terminationStatus
    }


    public func getBrowserCommand(url: URL, appPath: String, args: [String]) -> [String] {
        var command = ["open"]
        var commandArgs: [String] = []
        var appendUrl = true

        command.append(contentsOf: ["-a", appPath])

        if !args.isEmpty {
            commandArgs.append(contentsOf: args)

            // do not auto-append the URL when args has been explicitly defined
            appendUrl = false
        }

        if !commandArgs.isEmpty {
            command.append("-n")
            command.append("--args")
            command.append(contentsOf: commandArgs)
        }

        //if appendUrl {
            command.append(url.absoluteString)
        //}

        return command
    }

    /**
     * opens the url in the browser instance.
     */
    func openIn(browser: Browser) {
        let browserPath = browser.path
        let browserName = browser.name

        if browserPath.isEmpty {
            openInDefaultBrowser()
        } else {
            shell(getBrowserCommand(url: self, appPath: browserPath, args: browser.arguments.components(separatedBy: ",")))


//            let configuration = NSWorkspace.OpenConfiguration()
//            configuration.arguments = browser.arguments.components(separatedBy: ",")
//            configuration.createsNewApplicationInstance = true
//
//            NSWorkspace.shared.open([self], withApplicationAt: URL(fileURLWithPath: browserPath), configuration: configuration) { app, error in
//                guard app != nil else {
//                    NSLog("Can't open \(self) in \(browserName): \(String(describing: error?.localizedDescription))")
//                    sendNotification("Oops! Unable to open the link in \(browserName)", "Make sure you have \(browserName) installed, or change the browser in preferences.")
//                    self.openInDefaultBrowser()
//                    return
//                }
//                NSLog("Opening \(self) in \(browserName)")
//            }

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
