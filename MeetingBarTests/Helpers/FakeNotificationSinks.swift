//
//  FakeNotificationSinks.swift
//  MeetingBarTests
//

import UserNotifications
import XCTest

@testable import MeetingBar

/// In-memory `NotificationRequestSink` that records every call so reconcile
/// behaviour can be verified without touching the real notification center.
/// Calls are serialised by the test's `@MainActor` runner; no locking needed.
final class FakeNotificationRequestSink: NotificationRequestSink, @unchecked Sendable {
    private var pending: [UNNotificationRequest] = []
    private(set) var addedIdentifiers: [String] = []
    private(set) var removedBatches: [[String]] = []

    init(initialPending: [UNNotificationRequest] = []) {
        self.pending = initialPending
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        pending
    }

    func add(_ request: UNNotificationRequest) async throws {
        pending.append(request)
        addedIdentifiers.append(request.identifier)
    }

    func removePending(identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
        removedBatches.append(identifiers)
    }

    func currentPendingIdentifiers() -> [String] {
        pending.map(\.identifier)
    }

    func currentPendingRequests() -> [UNNotificationRequest] {
        pending
    }
}

@MainActor
final class FakeNotificationActionSink: NotificationActionSink {
    private let shouldPerform: Bool
    private(set) var attempts: [(kind: NotificationKind, eventID: String)] = []
    private(set) var actions: [(kind: NotificationKind, eventID: String)] = []

    init(shouldPerform: Bool = true) {
        self.shouldPerform = shouldPerform
    }

    func performNotificationAction(_ kind: NotificationKind, event: MBEvent) -> Bool {
        attempts.append((kind, event.id))
        guard shouldPerform else { return false }
        actions.append((kind, event.id))
        return true
    }
}
