//
//  DefaultsKeys.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Defaults

extension Defaults.Keys {
    static let calendarTitle = Key<String>("calendarTitle", default: "") // Backward compatibility
    static let selectedCalendars = Key<[String]>("selectedCalendars", default: []) // Backward compatibility
    static let selectedCalendarIDs = Key<[String]>("selectedCalendarIDs", default: [])
    static let useChromeForMeetLinks = Key<Bool>("useChromeForMeetLinks", default: false)
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let showEventDetails = Key<Bool>("showEventDetails", default: true)
    static let createMeetingService = Key<MeetingServices>("createMeetingService", default: .meet)
    static let showEventTitleInStatusBar = Key<Bool?>("showEventTitleInStatusBar", default: true)
    static let titleLength = Key<Double>("titleLength", default: TitleLengthLimits.max)
    static let timeFormat = Key<TimeFormat>("timeFormat", default: .military)
    static let etaFormat = Key<ETAFormat>("etaFormat", default: .short)
    static let eventTitleFormat = Key<EventTitleFormat>("eventTitleFormat", default: .show)
    static let declinedEventsAppereance = Key<DeclinedEventsAppereance>("declinedEventsAppereance", default: .strikethrough)
    static let disablePastEvents = Key<Bool>("disablePastEvents", default: true)
}
