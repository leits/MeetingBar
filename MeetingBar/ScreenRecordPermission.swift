//
//  ScreenRecordPermission.swift
//  MeetingBar
//
//  Created by t3adminjgol on 16.04.22.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import Foundation
import Cocoa

struct ScreenRecordPermission {
    
    /*
     * check if meetingbar has screen record permissions.
     */
    static func hasPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess();
        } else {
            return true
        }
    }

    /*
     * request screen record permission.
     * This permission is needed to detect if the 
     */
    static func requestPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestScreenCaptureAccess();
        }
        return true;
    }
    
    /*
     * check if any app has fullscreen
     */
    static func isFullScreen() -> Bool
    {
        if hasPermission() {
            
            guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) else {
                return false
            }
            
            for window in windows as NSArray
            {
                guard let winInfo = window as? NSDictionary else { continue }
                
                if winInfo["kCGWindowOwnerName"] as? String == "Dock",
                   winInfo["kCGWindowName"] as? String == "Fullscreen Backdrop"
                {
                    return true
                }
            }
            
            return false
        } else {
            if requestPermission() {
                return isFullScreen()
            }
            return false

            
        }
    }
}
