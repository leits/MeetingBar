//
//  MeetingBarLogger.swift
//  MeetingBar
//

import Foundation
import OSLog

enum MeetingBarLogger {
    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "leits.MeetingBar"

    static let calendar = Logger(subsystem: subsystem, category: "calendar-provider")
    static let meetingOpening = Logger(subsystem: subsystem, category: "meeting-opening")
    static let notifications = Logger(subsystem: subsystem, category: "notifications-snooze")
    static let patronage = Logger(subsystem: subsystem, category: "storekit-patronage")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle-tasks")
}
