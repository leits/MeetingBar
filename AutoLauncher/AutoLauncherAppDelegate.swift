//
//  AppDelegate.swift
//  AutoLauncher
//
//  Created by JOGENDRA on 13/09/20.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa

class AutoLauncherAppDelegate: NSObject, NSApplicationDelegate {
    struct Constants {
        static let mainAppBundleID = "leits.MeetingBar"
        static let mainAppName = "MeetingBar"
        static let appTargetPlatform = "MacOS"
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        launchOrTerminateMainApp()
    }

    /// Launch main application if it's not running already.
    /// Also, terminate the launcher app if it's not needed anymore.
    private func launchOrTerminateMainApp() {
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == Constants.mainAppBundleID }

        if !isRunning {
            let killAutoLauncherNotificationName = Notification.Name(rawValue: "killAutoLauncher")
            DistributedNotificationCenter.default().addObserver(self,
                                                                selector: #selector(self.terminateApp),
                                                                name: killAutoLauncherNotificationName,
                                                                object: Constants.mainAppBundleID)
            let path = Bundle.main.bundlePath as NSString
            var components = path.pathComponents
            // This Auto Launcher app is actually embedded inside the main app bundle
            // under the subdirectory Contents/Library/LoginItems.
            // So there will be a total of 3 path components to be deleted.
            for _ in 1...3 {
                components.removeLast()
            }
            components.append(Constants.appTargetPlatform)
            components.append(Constants.mainAppName)

            let actualAppPath = NSString.path(withComponents: components)
            NSWorkspace.shared.launchApplication(actualAppPath)
        } else {
            self.terminateApp()
        }
    }

    /// Terminate the app if the launcher is not needed anymore.
    @objc
    private func terminateApp() {
        NSApp.terminate(nil)
    }
}
