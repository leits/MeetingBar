//
//  AppIntent.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.03.2023.
//  Copyright © 2023 Andrii Leitsius. All rights reserved.
//

import AppIntents
import AppKit

@available(macOS 13.0, *)
enum EventDetailsTypeAppEnum: String, AppEnum {
    case title
    case startDate
    case endDate
    case meetingLink
    case meetingService
    case calendarTitle
    case url
    case notes
    case location
    case attendees

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Event Details Type")

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .title: "Title",
        .startDate: "Start Date",
        .endDate: "End Date",
        .meetingLink: "Meeting Link",
        .meetingService: "Meeting Service",
        .calendarTitle: "Calendar",
        .url: "URL",
        .notes: "Notes",
        .location: "Location",
        .attendees: "Attendees"
    ]
}

@available(macOS 13.0, *)
struct GetNearestEventDetails: AppIntent {
    static let title: LocalizedStringResource = "Get Nearest Event Details"
    static let description = IntentDescription(
        """
        Returns details about the nearest (curent or next) event.
        For example, title, meeting link, start date, end date, calendar, etc.
        """
    )

    @Parameter(title: "Type", default: .title)
    var type: EventDetailsTypeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Get the nearest event's \(\.$type)")
    }

    func perform() async throws
        -> some IntentResult & ReturnsValue<String?> {
        // Hop to the main actor only for the AppKit interaction
        let value: String? = await MainActor.run {
            guard
                let appDelegate = NSApplication.shared.delegate as? AppDelegate,
                let nextEvent = appDelegate.statusBarItem.events.nextEvent()
            else { return nil }

            switch type {
            case .title: return nextEvent.title
            case .calendarTitle: return nextEvent.calendar.title
            case .meetingLink: return nextEvent.meetingLink?.url.absoluteString
            case .meetingService: return nextEvent.meetingLink?.service?.localizedValue
            case .url: return nextEvent.url?.absoluteString
            case .notes: return nextEvent.notes
            case .location: return nextEvent.location
            case .startDate: return nextEvent.startDate.formatted()
            case .endDate: return nextEvent.endDate.formatted()
            case .attendees:
                return nextEvent.attendees.map { "\($0.name) <\($0.email ?? "unknown")>" }.joined(separator: ", ")
            }
        }
        return .result(value: value)
    }
}

@available(macOS 13.0, *)
struct JoinNearestMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Join Nearest Meeting"
    static let description = IntentDescription("Join the nearest (current or next) event meeting.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            (NSApplication.shared.delegate as? AppDelegate)?
                .statusBarItem
                .joinNextMeeting()
        }
        return .result()
    }
}

@available(macOS 13.0, *)
struct DismissNearestMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Dismiss Nearest Meeting"
    static let description = IntentDescription("Dismiss the nearest (current or next) event meeting.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            (NSApplication.shared.delegate as? AppDelegate)?
                .statusBarItem
                .dismissNextMeetingAction()
        }
        return .result()
    }
}
