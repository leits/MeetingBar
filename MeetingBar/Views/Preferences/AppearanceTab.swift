//
//  AppearanceTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults

struct AppearanceTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            EventsSection()
            Divider()
            StatusBarSection()
            Divider()
            MenuSection()
            Spacer()
        }.padding()
    }
}

struct StatusBarSection: View {
    @Default(.eventTitleIconFormat) var eventTitleIconFormat
    @Default(.eventTitleFormat) var eventTitleFormat
    @Default(.eventTimeFormat) var eventTimeFormat

    @Default(.statusbarEventTitleLength) var statusbarEventTitleLength


    var body: some View {
        Text("Status bar").font(.headline).bold()
        Section {
            HStack {
                Picker("Icon", selection: $eventTitleIconFormat) {
                    HStack {
                        Image(nsImage: getImage(iconName: EventTitleIconFormat.calendar.rawValue)).resizable()
                            .frame(width: 16.0, height: 16.0)
                        Text("\u{00A0}Calendar icon")
                    }.tag(EventTitleIconFormat.calendar)

                    HStack {
                        Image(nsImage: getImage(iconName: EventTitleIconFormat.appicon.rawValue)).resizable()
                            .frame(width: 16.0, height: 16.0)
                        Text("\u{00A0}App icon")
                    }.tag(EventTitleIconFormat.appicon)

                    HStack {
                        Image(nsImage: getImage(iconName: EventTitleIconFormat.eventtype.rawValue)).resizable()
                            .frame(width: 16.0, height: 16.0)
                        Text("\u{00A0}Event specific icon (e.g. MS Teams)")
                    }.tag(EventTitleIconFormat.eventtype)

                    HStack {
                        Image(nsImage: getImage(iconName: EventTitleIconFormat.none.rawValue)).resizable()
                            .frame(width: 16.0, height: 16.0)
                        Text("\u{00A0}No icon")
                    }.tag(EventTitleIconFormat.none)
                }
            }

            HStack {
                Picker("Title", selection: $eventTitleFormat) {
                    Text("event title").tag(EventTitleFormat.show)
                    Text("dot (•)").tag(EventTitleFormat.dot)
                    Text("hide").tag(EventTitleFormat.none)
                }
                if eventTitleFormat == EventTitleFormat.show {
                    Stepper("shorten to \(statusbarEventTitleLength) chars", value: $statusbarEventTitleLength, in: statusbarEventTitleLengthLimits.min...statusbarEventTitleLengthLimits.max, step: 5)
                }
            }
            HStack {
                Picker("Time", selection: $eventTimeFormat) {
                    Text("show").tag(EventTimeFormat.show)
                    Text("show under title").tag(EventTimeFormat.show_under_title)
                    Text("hide").tag(EventTimeFormat.hide)
                }
            }
        }.padding(.horizontal, 10)
    }

    func getImage(iconName: String) -> NSImage {
        let icon = NSImage(named: iconName)
        icon!.size = NSSize(width: 16, height: 16)
        return icon!
    }
}

struct MenuSection: View {
    @Default(.timeFormat) var timeFormat
    @Default(.shortenEventTitle) var shortenEventTitle
    @Default(.menuEventTitleLength) var menuEventTitleLength
    @Default(.showEventEndTime) var showEventEndTime
    @Default(.showEventDetails) var showEventDetails
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon

    var body: some View {
        Text("Menu").font(.headline).bold()
        Section {
            HStack {
                Toggle("Shorten event title to", isOn: $shortenEventTitle)
                Stepper("\(menuEventTitleLength) chars", value: $menuEventTitleLength, in: 20...100, step: 5).disabled(!shortenEventTitle)
            }
            Group {
                HStack {
                    Picker("Time format:", selection: $timeFormat) {
                        Text("12-hour (AM/PM)").tag(TimeFormat.am_pm)
                        Text("24-hour").tag(TimeFormat.military)
                    }
                }
                HStack {
                    Text("Show event:")
                    Toggle("end time", isOn: $showEventEndTime)
                    Toggle("icon", isOn: $showMeetingServiceIcon)
                    Toggle("details as submenu", isOn: $showEventDetails)
                }
            }
        }.padding(.horizontal, 10)
    }
}

struct EventsSection: View {
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.personalEventsAppereance) var personalEventsAppereance
    @Default(.pastEventsAppereance) var pastEventsAppereance
    @Default(.allDayEvents) var allDayEvents
    @Default(.showPendingEvents) var showPendingEvents
    @Default(.showEventsForPeriod) var showEventsForPeriod
    @Default(.showEventMaxTimeUntilEventThreshold) var showEventMaxTimeUntilEventThreshold
    @Default(.showEventMaxTimeUntilEventEnabled) var showEventMaxTimeUntilEventEnabled

    var body: some View {
        Text("Events").font(.headline).bold()
        Section {
            HStack {
                Picker("Show events for", selection: $showEventsForPeriod) {
                    Text("today").tag(ShowEventsForPeriod.today)
                    Text("today and tomorrow").tag(ShowEventsForPeriod.today_n_tomorrow)
                }
                Picker("All day events:", selection: $allDayEvents) {
                    Text("show").tag(AlldayEventsAppereance.show)
                    Text("show only with meeting link").tag(AlldayEventsAppereance.show_with_meeting_link_only)
                    Text("hide").tag(AlldayEventsAppereance.hide)
                }
            }
            HStack {
                Toggle("Show only events starting in", isOn: $showEventMaxTimeUntilEventEnabled)
                Stepper("\(showEventMaxTimeUntilEventThreshold) minutes", value: $showEventMaxTimeUntilEventThreshold, in: 5...120, step: 5)
                    .disabled(!showEventMaxTimeUntilEventEnabled)
            }

            HStack {
                Picker("Events without guests:", selection: $personalEventsAppereance) {
                    Text("show").tag(PastEventsAppereance.show_active)
                    Text("show as inactive").tag(PastEventsAppereance.show_inactive)
                    Text("hide").tag(PastEventsAppereance.hide)
                }
                Picker("Past events:", selection: $pastEventsAppereance) {
                    Text("show").tag(PastEventsAppereance.show_active)
                    Text("show as inactive").tag(PastEventsAppereance.show_inactive)
                    Text("hide").tag(PastEventsAppereance.hide)
                }
            }
            HStack {
                Picker("Pending events", selection: $showPendingEvents) {
                    Text("show").tag(PendingEventsAppereance.show)
                    Text("show as underlined").tag(PendingEventsAppereance.show_underlined)
                    Text("show as inactive").tag(PendingEventsAppereance.show_inactive)
                    Text("hide").tag(PendingEventsAppereance.hide)
                }

                Picker("Declined events:", selection: $declinedEventsAppereance) {
                    Text("show with strikethrough").tag(DeclinedEventsAppereance.strikethrough)
                    Text("show as inactive").tag(DeclinedEventsAppereance.show_inactive)
                    Text("hide").tag(DeclinedEventsAppereance.hide)
                }
            }
        }.padding(.horizontal, 10)
    }
}
