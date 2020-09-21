//
//  DefaultsKeys.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Defaults

extension Defaults.Keys {
    // General
    static let calendarTitle = Key<String>("calendarTitle", default: "") // Backward compatibility
    static let selectedCalendars = Key<[String]>("selectedCalendars", default: []) // Backward compatibility
    static let selectedCalendarIDs = Key<[String]>("selectedCalendarIDs", default: [])

    static let onboardingCompleted = Key<Bool>("onboardingCompleted", default: false)

    static let showEventsForPeriod = Key<ShowEventsForPeriod>("showEventsForPeriod", default: .today)
    static let joinEventNotification = Key<Bool>("joinEventNotification", default: true)
    static let joinEventNotificationTime = Key<JoinEventNotificationTime>("joinEventNotificationTime", default: .atStart)
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)


    // Status Bar Appearance
    static let showEventTitleInStatusBar = Key<Bool?>("showEventTitleInStatusBar", default: nil) // Backward compatibility
    static let eventTitleFormat = Key<EventTitleFormat>("eventTitleFormat", default: .show)
    static let titleLength = Key<Double>("titleLength", default: TitleLengthLimits.max)

    // Menu Appearance
    static let showEventDetails = Key<Bool>("showEventDetails", default: false)
    static let declinedEventsAppereance = Key<DeclinedEventsAppereance>("declinedEventsAppereance", default: .strikethrough)
    static let disablePastEvents = Key<Bool>("disablePastEvents", default: true)
    static let hidePastEvents = Key<Bool>("hidePastEvents", default: false)
    static let timeFormat = Key<TimeFormat>("timeFormat", default: .military)

    // Integrations
    static let createMeetingService = Key<MeetingServices>("createMeetingService", default: .zoom)
    static let useChromeForMeetLinks = Key<Bool>("useChromeForMeetLinks", default: false)
    static let useChromeForHangoutsLinks = Key<Bool>("useChromeForHangoutsLinks", default: false)
    static let useAppForZoomLinks = Key<Bool>("useAppForZoomLinks", default: false)
    static let useAppForTeamsLinks = Key<Bool>("useAppForTeamsLinks", default: false)
}
