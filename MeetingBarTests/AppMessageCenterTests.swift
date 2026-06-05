//
//  AppMessageCenterTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class AppMessageMappingTests: XCTestCase {
    func testMeetingAndPatronageMessagesUseLocalizedContent() {
        XCTAssertEqual(
            AppMessage.meetingLinkMissing(title: "Standup").content,
            AppMessageContent(
                title: "status_bar_error_link_missed_title".loco("Standup"),
                text: "status_bar_error_link_missed_message".loco(),
                presentation: .notificationOrAlert
            )
        )
        XCTAssertEqual(
            AppMessage.patronagePurchaseSucceeded.content.title,
            "store_patronage_title".loco()
        )
    }

    func testScriptFailuresRequireAlertPresentation() {
        XCTAssertEqual(
            AppMessage.eventScriptFileMissing(path: "/scripts").content.presentation,
            .alert
        )
    }
}

final class AppMessageCenterTests: XCTestCase {
    func testNotificationPathUsesUserNotification() async {
        let recorder = MessageRecorder()
        let center = makeCenter(notificationsEnabled: true, recorder: recorder)

        await center.present(.nextMeetingMissing)

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.notifications.count, 1)
        XCTAssertTrue(snapshot.alerts.isEmpty)
    }

    func testDisabledNotificationsFallBackToAlert() async {
        let recorder = MessageRecorder()
        let center = makeCenter(notificationsEnabled: false, recorder: recorder)

        await center.present(.nextMeetingMissing)

        let snapshot = await recorder.snapshot()
        XCTAssertTrue(snapshot.notifications.isEmpty)
        XCTAssertEqual(snapshot.alerts.count, 1)
    }

    func testForcedAlertSkipsNotificationCheck() async {
        let recorder = MessageRecorder()
        let center = makeCenter(notificationsEnabled: true, recorder: recorder)

        await center.present(.eventScriptFileMissing(path: "/scripts"))

        let snapshot = await recorder.snapshot()
        XCTAssertTrue(snapshot.notifications.isEmpty)
        XCTAssertEqual(snapshot.alerts.count, 1)
    }

    private func makeCenter(
        notificationsEnabled: Bool,
        recorder: MessageRecorder
    ) -> AppMessageCenter {
        AppMessageCenter(
            notificationsEnabled: { notificationsEnabled },
            sendUserNotification: { title, text in
                await recorder.recordNotification(title: title, text: text)
            },
            displayAlert: { title, text in
                await recorder.recordAlert(title: title, text: text)
            }
        )
    }
}

private actor MessageRecorder {
    private var notifications: [(String, String)] = []
    private var alerts: [(String, String)] = []

    func recordNotification(title: String, text: String) {
        notifications.append((title, text))
    }

    func recordAlert(title: String, text: String) {
        alerts.append((title, text))
    }

    func snapshot() -> (notifications: [(String, String)], alerts: [(String, String)]) {
        (notifications, alerts)
    }
}
