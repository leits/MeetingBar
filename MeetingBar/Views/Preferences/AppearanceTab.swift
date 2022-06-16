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
    @Default(.showEventMaxTimeUntilEventThreshold) var showEventMaxTimeUntilEventThreshold
    @Default(.showEventMaxTimeUntilEventEnabled) var showEventMaxTimeUntilEventEnabled
    
    var body: some View {
        Text("preferences_appearance_status_bar_title".loco()).font(.headline).bold()
        Section {
            HStack {
                Picker("preferences_appearance_status_bar_icon_title".loco(), selection: $eventTitleIconFormat) {
                    HStack {
                        Image(nsImage: getImage(iconName: EventTitleIconFormat.calendar.rawValue)).resizable()
                            .frame(width: 16.0, height: 16.0)
                        Text("preferences_appearance_status_bar_icon_calendar_icon_value".loco())
                    }.tag(EventTitleIconFormat.calendar)

                    HStack {
                        Image(nsImage: getImage(iconName: EventTitleIconFormat.appicon.rawValue)).resizable()
                            .frame(width: 16.0, height: 16.0)
                        Text("preferences_appearance_status_bar_icon_app_icon_value".loco())
                    }.tag(EventTitleIconFormat.appicon)

                    HStack {
                        Image(nsImage: getImage(iconName: EventTitleIconFormat.eventtype.rawValue)).resizable()
                            .frame(width: 16.0, height: 16.0)
                        Text("preferences_appearance_status_bar_icon_specific_icon_value".loco())
                    }.tag(EventTitleIconFormat.eventtype)

                    HStack {
                        Image(nsImage: getImage(iconName: EventTitleIconFormat.none.rawValue)).resizable()
                            .frame(width: 16.0, height: 16.0)
                        Text("preferences_appearance_status_bar_icon_no_icon_value".loco())
                    }.tag(EventTitleIconFormat.none)
                }
            }.frame(width: 300)

            HStack {
                Picker("preferences_appearance_status_bar_title_title".loco(), selection: $eventTitleFormat) {
                    Text("preferences_appearance_status_bar_title_event_title_value".loco()).tag(EventTitleFormat.show)
                    Text("preferences_appearance_status_bar_title_dot_value".loco()).tag(EventTitleFormat.dot)
                    Text("preferences_appearance_status_bar_title_hide_value".loco()).tag(EventTitleFormat.none)
                }.frame(width: 300)
                if eventTitleFormat == EventTitleFormat.show {
                    Stepper("preferences_appearance_status_bar_title_shorten_stepper".loco(statusbarEventTitleLength),
                            value: $statusbarEventTitleLength,
                            in: statusbarEventTitleLengthLimits.min ... statusbarEventTitleLengthLimits.max,
                            step: 5)
                }
            }
            HStack {
                Picker("preferences_appearance_status_bar_time_title".loco(), selection: $eventTimeFormat) {
                    Text("preferences_appearance_status_bar_time_show_value".loco()).tag(EventTimeFormat.show)
                    if #available(OSX 11.0, *) {} else {
                        Text("preferences_appearance_status_bar_time_show_under_title_value".loco()).tag(EventTimeFormat.show_under_title)
                    }
                    Text("preferences_appearance_status_bar_time_hide_value".loco()).tag(EventTimeFormat.hide)
                }
            }.frame(width: 300)

            HStack {
                Toggle("preferences_appearance_status_bar_next_event_toggle".loco(), isOn: $showEventMaxTimeUntilEventEnabled)
                Stepper("preferences_appearance_status_bar_next_event_stepper".loco(showEventMaxTimeUntilEventThreshold), value: $showEventMaxTimeUntilEventThreshold, in: 5 ... 720, step: 5)
                    .disabled(!showEventMaxTimeUntilEventEnabled)
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
    @Default(.bookmarksCollapseAfter) var bookmarksCollapseAfter
    
    var body: some View {
        Text("preferences_appearance_menu_title".loco()).font(.headline).bold()
        Section {
            HStack {
                Toggle("preferences_appearance_menu_shorten_event_title_toggle".loco(), isOn: $shortenEventTitle)
                Stepper("preferences_appearance_menu_shorten_event_title_stepper".loco(menuEventTitleLength), value: $menuEventTitleLength, in: 20 ... 100, step: 5).disabled(!shortenEventTitle)
            }
            Group {
                HStack {
                    Picker("preferences_appearance_menu_time_format_title".loco(), selection: $timeFormat) {
                        Text("preferences_appearance_menu_time_format_12_hour_value".loco()).tag(TimeFormat.am_pm)
                        Text("preferences_appearance_menu_time_format_24_hour_value".loco()).tag(TimeFormat.military)
                    }
                }.frame(width: 300)
                HStack {
                    Text("preferences_appearance_menu_show_event_title".loco())
                    Toggle("preferences_appearance_menu_show_event_end_time_value".loco(), isOn: $showEventEndTime)
                    Toggle("preferences_appearance_menu_show_event_icon_value".loco(), isOn: $showMeetingServiceIcon)
                    Toggle("preferences_appearance_menu_show_event_details_value".loco(), isOn: $showEventDetails)
                }
            }
            HStack {
                Text("preferences_appearance_menu_collapse_bookmarks_after_title".loco())
                Stepper(
                    "preferences_appearance_menu_collapse_bookmarks_after_stepper_\(bookmarksCollapseAfter != 1 ? "plural" : "singular")".loco(bookmarksCollapseAfter),
                    value: $bookmarksCollapseAfter, in: 0 ... 100, step: 1)
            }
        }.padding(.horizontal, 10)
    }
}

struct EventsSection: View {
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.personalEventsAppereance) var personalEventsAppereance
    @Default(.pastEventsAppereance) var pastEventsAppereance
    @Default(.allDayEvents) var allDayEvents
    @Default(.nonAllDayEvents) var nonAllDayEvents
    @Default(.showPendingEvents) var showPendingEvents
    @Default(.showEventsForPeriod) var showEventsForPeriod

    var body: some View {
        Text("preferences_appearance_events_title".loco()).font(.headline).bold()
        Section {
            HStack {
                Picker("preferences_appearance_events_show_events_for_title".loco(), selection: $showEventsForPeriod) {
                    Text("preferences_appearance_events_show_events_for_today_value".loco()).tag(ShowEventsForPeriod.today)
                    Text("preferences_appearance_events_show_events_for_today_tomorrow_value".loco()).tag(ShowEventsForPeriod.today_n_tomorrow)
                }.frame(width: 300)
            }

            HStack {
                Picker("preferences_appearance_events_all_day_title".loco(), selection: $allDayEvents) {
                    Text("preferences_appearance_events_value_show".loco()).tag(AlldayEventsAppereance.show)
                    Text("preferences_appearance_events_value_only_with_link".loco()).tag(AlldayEventsAppereance.show_with_meeting_link_only)
                    Text("preferences_appearance_events_value_hide".loco()).tag(AlldayEventsAppereance.hide)
                }

                Picker("preferences_appearance_events_non_all_day_title".loco(), selection: $nonAllDayEvents) {
                    Text("preferences_appearance_events_value_show".loco()).tag(NonAlldayEventsAppereance.show)
                    Text("preferences_appearance_events_value_inactive_without_meeting_link".loco()).tag(NonAlldayEventsAppereance.show_inactive_without_meeting_link)
                    Text("preferences_appearance_events_value_hide_without_meeting_link".loco()).tag(NonAlldayEventsAppereance.hide_without_meeting_link)
                }
            }

            HStack {
                Picker("preferences_appearance_events_without_guest_title".loco(), selection: $personalEventsAppereance) {
                    Text("preferences_appearance_events_value_show".loco()).tag(PastEventsAppereance.show_active)
                    Text("preferences_appearance_events_value_as_inactive".loco()).tag(PastEventsAppereance.show_inactive)
                    Text("preferences_appearance_events_value_hide".loco()).tag(PastEventsAppereance.hide)
                }
                Picker("preferences_appearance_events_past_title".loco(), selection: $pastEventsAppereance) {
                    Text("preferences_appearance_events_value_show".loco()).tag(PastEventsAppereance.show_active)
                    Text("preferences_appearance_events_value_as_inactive".loco()).tag(PastEventsAppereance.show_inactive)
                    Text("preferences_appearance_events_value_hide".loco()).tag(PastEventsAppereance.hide)
                }
            }
            HStack {
                Picker("preferences_appearance_events_pending_title".loco(), selection: $showPendingEvents) {
                    Text("preferences_appearance_events_value_show".loco()).tag(PendingEventsAppereance.show)
                    Text("preferences_appearance_events_value_as_underlined".loco()).tag(PendingEventsAppereance.show_underlined)
                    Text("preferences_appearance_events_value_as_inactive".loco()).tag(PendingEventsAppereance.show_inactive)
                    Text("preferences_appearance_events_value_hide".loco()).tag(PendingEventsAppereance.hide)
                }

                Picker("preferences_appearance_events_declined_title".loco(), selection: $declinedEventsAppereance) {
                    Text("preferences_appearance_events_value_with_strikethrough".loco()).tag(DeclinedEventsAppereance.strikethrough)
                    Text("preferences_appearance_events_value_as_inactive".loco()).tag(DeclinedEventsAppereance.show_inactive)
                    Text("preferences_appearance_events_value_hide".loco()).tag(DeclinedEventsAppereance.hide)
                }
            }
        }.padding(.horizontal, 10)
    }
}
