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
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains {
            $0.bundleIdentifier == Constants.mainAppBundleID
        }

        if !isRunning {
            var path = Bundle.main.bundlePath as NSString
            // This Auto Launcher app is actually embedded inside the main app bundle
            // under the subdirectory Contents/Library/LoginItems.
            // So including the helper app name there will be a
            // total of 4 path components to be deleted.
            for _ in 1...4 {
                path = path.deletingLastPathComponent as NSString
            }
            let applicationPathString = path as String
            guard let pathURL = URL(string: applicationPathString) else { return }
            NSWorkspace.shared.openApplication(at: pathURL,
                                               configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

}
