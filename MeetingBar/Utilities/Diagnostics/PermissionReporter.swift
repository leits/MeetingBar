//
//  PermissionReporter.swift
//  MeetingBar
//
//  Populates `PermissionSnapshot` (defined in `DiagnosticsReport.swift`) from
//  the real EventKit / UserNotifications APIs. Lives in the host target so
//  the hostless logic package can still depend on the snapshot type.
//

import EventKit
import Foundation
import UserNotifications

enum PermissionReporter {
    @MainActor
    static func current(provider: EventStoreProvider) async -> PermissionSnapshot {
        let calendarAccess = calendarAuthStatus()
        let notificationAccess = await notificationAuthStatus()
        let googleAuthStatus: PermissionSnapshot.GoogleAuthStatus = provider == .googleCalendar
            ? (GCEventStore.shared.isAuthorized ? .authorized : .notAuthorized)
            : .notActive
        let scriptFileExists = scriptExists()
        let isAppStoreBuild = Bundle.main.appStoreReceiptURL?.lastPathComponent == "receipt"
        return PermissionSnapshot(
            calendarAccess: calendarAccess,
            notificationAccess: notificationAccess,
            googleAuthStatus: googleAuthStatus,
            scriptFileExists: scriptFileExists,
            isAppStoreBuild: isAppStoreBuild
        )
    }

    private static func calendarAuthStatus() -> PermissionSnapshot.CalendarAccess {
        if #available(macOS 14, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined: return .notDetermined
            case .restricted: return .restricted
            case .denied: return .denied
            case .fullAccess, .writeOnly: return .authorized
            @unknown default: return .notDetermined
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined: return .notDetermined
            case .restricted: return .restricted
            case .denied: return .denied
            case .authorized: return .authorized
            @unknown default: return .notDetermined
            }
        }
    }

    private static func notificationAuthStatus() async -> PermissionSnapshot.NotificationAccess {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional, .ephemeral: return .provisional
        @unknown default: return .notDetermined
        }
    }

    private static func scriptExists() -> Bool {
        guard let dir = try? FileManager.default.url(
            for: .applicationScriptsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("eventStartScript.scpt").path)
    }
}
