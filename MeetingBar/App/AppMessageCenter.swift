//
//  AppMessageCenter.swift
//  MeetingBar
//

import AppKit
import Foundation
import UserNotifications

enum AppMessagePresentation: Equatable, Sendable {
    case notificationOrAlert
    case alert
}

struct AppMessageContent: Equatable, Sendable {
    let title: String
    let text: String
    let presentation: AppMessagePresentation
}

enum AppMessage: Equatable, Sendable {
    case nextMeetingMissing
    case meetingDismissed(title: String)
    case allDismissalsRemoved
    case meetingLinkMissing(title: String)
    case meetingAppUnavailable(name: String)
    case createMeetingInvalidURL(value: String)
    case browserUnavailable(name: String)
    case defaultBrowserUnavailable
    case clipboardInvalid
    case clipboardEmpty
    case joinScriptFailed(description: String)
    case eventScriptExecutionFailed(path: String, description: String)
    case eventScriptFileMissing(path: String)
    case googleAccountConnected(email: String)
    case patronagePurchaseSucceeded
    case patronageRestoreSucceeded
    case patronageRestoreEmpty
    case patronagePaymentNotAllowed
    case patronageProductUnavailable
    case patronageNetworkFailed
    case patronageUnknownError
    case patronageFailure(description: String)

    var content: AppMessageContent {
        switch self {
        case .nextMeetingMissing:
            notification(
                title: "next_meeting_empty_title".loco(),
                text: "next_meeting_empty_message".loco()
            )
        case .meetingDismissed(let title):
            notification(
                title: "notification_next_meeting_dismissed_title".loco(title),
                text: "notification_next_meeting_dismissed_message".loco()
            )
        case .allDismissalsRemoved:
            notification(
                title: "notification_all_dismissals_removed_title".loco(),
                text: "notification_all_dismissals_removed_message".loco()
            )
        case .meetingLinkMissing(let title):
            notification(
                title: "status_bar_error_link_missed_title".loco(title),
                text: "status_bar_error_link_missed_message".loco()
            )
        case .meetingAppUnavailable(let name):
            notification(
                title: "status_bar_error_app_link_title".loco(name),
                text: "status_bar_error_app_link_message".loco(name)
            )
        case .createMeetingInvalidURL(let value):
            notification(
                title: "create_meeting_error_title".loco(),
                text: "create_meeting_error_message".loco(value)
            )
        case .browserUnavailable(let name):
            notification(
                title: "link_url_cant_open_title".loco(name),
                text: "link_url_cant_open_message".loco(name)
            )
        case .defaultBrowserUnavailable:
            notification(
                title: "link_url_cant_open_title".loco(
                    "preferences_services_link_default_browser_value".loco()
                ),
                text: "preferences_services_create_meeting_custom_url_placeholder".loco()
            )
        case .clipboardInvalid:
            notification(
                title: "message_clipboard_invalid_title".loco(),
                text: "message_clipboard_invalid_text".loco()
            )
        case .clipboardEmpty:
            notification(
                title: "message_clipboard_empty_title".loco(),
                text: "message_clipboard_empty_text".loco()
            )
        case .joinScriptFailed(let description):
            notification(
                title: "status_bar_error_apple_script_title".loco(),
                text: description
            )
        case .eventScriptExecutionFailed(let path, let description):
            alert(
                title: "message_event_script_execution_failed_title".loco(),
                text: "message_event_script_execution_failed_text".loco(path, description)
            )
        case .eventScriptFileMissing(let path):
            alert(
                title: "message_event_script_file_missing_title".loco(),
                text: "message_event_script_file_missing_text".loco(path)
            )
        case .googleAccountConnected(let email):
            notification(
                title: "message_google_account_connected_title".loco(),
                text: "message_google_account_connected_text".loco(email)
            )
        case .patronagePurchaseSucceeded:
            patronage("store_patronage_purchase_success_message")
        case .patronageRestoreSucceeded:
            patronage("store_patronage_restore_success_message")
        case .patronageRestoreEmpty:
            patronage("store_patronage_restore_nothing_message")
        case .patronagePaymentNotAllowed:
            patronage("store_patronage_purchase_payment_not_allowed_message")
        case .patronageProductUnavailable:
            patronage("store_patronage_purchase_store_product_not_available_message")
        case .patronageNetworkFailed:
            patronage("store_patronage_purchase_cloud_service_network_connection_failed")
        case .patronageUnknownError:
            patronage("store_patronage_purchase_unknown_message")
        case .patronageFailure(let description):
            notification(title: "store_patronage_title".loco(), text: description)
        }
    }

    private func notification(title: String, text: String) -> AppMessageContent {
        AppMessageContent(title: title, text: text, presentation: .notificationOrAlert)
    }

    private func alert(title: String, text: String) -> AppMessageContent {
        AppMessageContent(title: title, text: text, presentation: .alert)
    }

    private func patronage(_ textKey: String) -> AppMessageContent {
        notification(title: "store_patronage_title".loco(), text: textKey.loco())
    }
}

struct AppMessageCenter: Sendable {
    typealias NotificationsEnabled = @Sendable () async -> Bool
    typealias SendUserNotification = @Sendable (String, String) async -> Void
    typealias DisplayAlert = @MainActor @Sendable (String, String) async -> Void

    static let shared = AppMessageCenter(
        notificationsEnabled: {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let styleOK = settings.alertStyle == .alert || settings.alertStyle == .banner
            return styleOK && settings.authorizationStatus != .denied
        },
        sendUserNotification: { title, text in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = text
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                let errorDescription = String(describing: error)
                MeetingBarLogger.notifications.error(
                    "Could not present user message: \(errorDescription, privacy: .private)"
                )
            }
        },
        displayAlert: { title, text in
            guard !AppMessageCenter.shouldSuppressSystemUI() else { return }
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = text
            alert.alertStyle = .informational
            alert.addButton(withTitle: "general_ok".loco())
            alert.runModal()
        }
    )

    static func shouldSuppressSystemUI(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        xctestLoaded: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Bool {
        xctestLoaded || environment["XCTestConfigurationFilePath"] != nil
    }

    private let notificationsEnabled: NotificationsEnabled
    private let sendUserNotification: SendUserNotification
    private let displayAlert: DisplayAlert

    init(
        notificationsEnabled: @escaping NotificationsEnabled,
        sendUserNotification: @escaping SendUserNotification,
        displayAlert: @escaping DisplayAlert
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.sendUserNotification = sendUserNotification
        self.displayAlert = displayAlert
    }

    func post(_ message: AppMessage) {
        Task {
            await present(message)
        }
    }

    func present(_ message: AppMessage) async {
        let content = message.content
        if content.presentation == .alert {
            await displayAlert(content.title, content.text)
        } else if await notificationsEnabled() {
            await sendUserNotification(content.title, content.text)
        } else {
            await displayAlert(content.title, content.text)
        }
    }
}
