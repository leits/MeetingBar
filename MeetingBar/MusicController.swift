//
//  Music.swift
//  MeetingBar
//
//  Created by Colin Edwards on 10/9/20.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Foundation
import ScriptingBridge

class MusicController {
    static func pauseMusic() {
        if let application = SBApplication(bundleIdentifier: "com.apple.Music") {
            if application.isRunning {
                let music = application as MusicApplication
                music.pause?()
            }
        }
    }
}
