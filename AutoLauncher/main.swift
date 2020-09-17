//
//  main.swift
//  AutoLauncher
//
//  Created by JOGENDRA on 13/09/20.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa

let delegate = AutoLauncherAppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
