//
//  AppDelegate.swift
//  AutoLauncher
//
//  Created by JOGENDRA on 13/09/20.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import SwiftUI

@NSApplicationMain
class AutoLauncherAppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains {
            $0.bundleIdentifier == "leits.MeetingBar.AutoLauncher"
        }
        
        if !isRunning {
            var path = Bundle.main.bundlePath as NSString
            for _ in 1...4 {
                path = path.deletingLastPathComponent as NSString
            }
            NSWorkspace.shared.launchApplication(path as String)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

