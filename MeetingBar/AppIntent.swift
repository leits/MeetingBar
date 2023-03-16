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

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Event Details Type")

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .title: "Title",
        .startDate: "Start date",
        .endDate: "End date",
        .meetingLink: "Meeting link",
        .meetingService: "Meeting service",
        .calendarTitle: "Title of the event calendar",
        .url: "Content of URL filed",
        .notes: "Content of notes field",
        .location: "Content of location filed"
    ]
}

@available(macOS 13.0, *)
struct GetNextEventDetails: AppIntent, CustomIntentMigratedAppIntent {
    static let intentClassName = "GetNextEventDetailsIntent"

    static let title: LocalizedStringResource = "Get Next Event Details"

    static let description = IntentDescription(
        """
        Returns details about the next or current event.
        For example, title, meeting link, start date, end date, location, etc.
        """,
        categoryName: "Next event"
    )

    @Parameter(title: "Type", default: .title)
    var type: EventDetailsTypeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Get the next event's \(\.$type)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        guard let app = await NSApplication.shared.delegate as! AppDelegate? else {
            return .result(value: nil)
        }
        guard let nextEvent = getNextEvent(events: app.statusBarItem.events) else {
            return .result(value: nil)
        }

        let result: String? = { () -> String? in
            switch type {
            case .title:
                return nextEvent.title
            case .calendarTitle:
                return nextEvent.calendar.title
            case .meetingLink:
                return nextEvent.meetingLink?.url.absoluteString
            case .meetingService:
                return nextEvent.meetingLink?.service?.localizedValue
            case .url:
                return nextEvent.url?.absoluteString
            case .notes:
                return nextEvent.notes
            case .location:
                return nextEvent.location
            case .startDate:
                return nextEvent.startDate.formatted()
            case .endDate:
                return nextEvent.endDate.formatted()
            }
        }()

        return .result(value: result)
    }
}

@available(macOS 13.0, *)
struct JoinNextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Join next meeting"

    static let description = IntentDescription(
        """
        Join next event meeting.
        """,
        categoryName: "Next event"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Open link to the next or current event.")
    }

    func perform() async throws -> some IntentResult {
        if let app = await NSApplication.shared.delegate as! AppDelegate? {
            app.statusBarItem.joinNextMeeting()
        }
        return .result()
    }
}
