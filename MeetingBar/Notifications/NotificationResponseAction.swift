//
//  NotificationResponseAction.swift
//  MeetingBar
//

import Foundation

enum EventNotificationIdentifiers {
    static let eventCategory = "EVENT"
    static let snoozeCategory = "SNOOZE_EVENT"
    static let joinAction = "JOIN_ACTION"
    static let dismissAction = "DISMISS_ACTION"

    static let supportedCategories = [eventCategory, snoozeCategory]
}

/// App-level meaning of a user interaction with an event notification.
///
/// The system notification delegate parses framework values into this type,
/// then AppModel owns the resulting workflow.
enum NotificationResponseAction: Equatable {
    case join(eventID: String)
    case dismiss(eventID: String)
    case snooze(eventID: String, action: NotificationEventTimeAction)

    init?(
        categoryIdentifier: String,
        actionIdentifier: String,
        eventID: String?,
        defaultActionIdentifier: String
    ) {
        guard
            EventNotificationIdentifiers.supportedCategories.contains(categoryIdentifier),
            let eventID
        else {
            return nil
        }

        switch actionIdentifier {
        case EventNotificationIdentifiers.joinAction, defaultActionIdentifier:
            self = .join(eventID: eventID)
        case EventNotificationIdentifiers.dismissAction:
            self = .dismiss(eventID: eventID)
        default:
            guard let action = NotificationEventTimeAction(rawValue: actionIdentifier) else {
                return nil
            }
            self = .snooze(eventID: eventID, action: action)
        }
    }
}
