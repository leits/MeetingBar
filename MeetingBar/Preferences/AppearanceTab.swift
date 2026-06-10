//
//  AppearanceTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

private struct SettingsRow<Control: View>: View {
    let title: String
    let control: Control

    init(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            control
                .frame(minWidth: 180)
        }
        .padding(.vertical, 6)
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct AppearanceTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EventsSection()
            Divider().padding(.vertical, 12)
            StatusBarSection()
            Divider().padding(.vertical, 12)
            MenuSection()
            Spacer()
        }
    }
}

struct EventsSection: View {
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.personalEventsAppereance) var personalEventsAppereance
    @Default(.pastEventsAppereance) var pastEventsAppereance
    @Default(.allDayEvents) var allDayEvents
    @Default(.nonAllDayEvents) var nonAllDayEvents
    @Default(.showPendingEvents) var showPendingEvents
    @Default(.showTentativeEvents) var showTentativeEvents
    @Default(.showEventsForPeriod) var showEventsForPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "events", systemImage: "calendar.day.timeline.left")

            VStack(alignment: .leading, spacing: 10) {
                SettingsRow("preferences_appearance_events_show_events_for_title".loco()) {
                    Picker("", selection: $showEventsForPeriod) {
                        Text("preferences_appearance_events_show_events_for_today_value".loco())
                            .tag(ShowEventsForPeriod.today)
                        Text("preferences_appearance_events_show_events_for_today_tomorrow_value".loco())
                            .tag(ShowEventsForPeriod.today_n_tomorrow)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_events_all_day_title".loco()) {
                    Picker("", selection: $allDayEvents) {
                        Text("preferences_appearance_events_value_show".loco()).tag(AlldayEventsAppereance.show)
                        Text("preferences_appearance_events_value_only_with_link".loco())
                            .tag(AlldayEventsAppereance.show_with_meeting_link_only)
                        Text("preferences_appearance_events_value_hide".loco()).tag(AlldayEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_events_non_all_day_title".loco()) {
                    Picker("", selection: $nonAllDayEvents) {
                        Text("preferences_appearance_events_value_show".loco()).tag(NonAlldayEventsAppereance.show)
                        Text("preferences_appearance_events_value_inactive_without_meeting_link".loco())
                            .tag(NonAlldayEventsAppereance.show_inactive_without_meeting_link)
                        Text("preferences_appearance_events_value_hide_without_meeting_link".loco())
                            .tag(NonAlldayEventsAppereance.hide_without_meeting_link)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_events_without_guest_title".loco()) {
                    Picker("", selection: $personalEventsAppereance) {
                        Text("preferences_appearance_events_value_show".loco()).tag(PastEventsAppereance.show_active)
                        Text("preferences_appearance_events_value_as_inactive".loco()).tag(PastEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco()).tag(PastEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_events_pending_title".loco()) {
                    Picker("", selection: $showPendingEvents) {
                        Text("preferences_appearance_events_value_show".loco()).tag(PendingEventsAppereance.show)
                        Text("preferences_appearance_events_value_as_underlined".loco()).tag(PendingEventsAppereance.show_underlined)
                        Text("preferences_appearance_events_value_as_inactive".loco()).tag(PendingEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco()).tag(PendingEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_events_tentative_title".loco()) {
                    Picker("", selection: $showTentativeEvents) {
                        Text("preferences_appearance_events_value_show".loco()).tag(TentativeEventsAppereance.show)
                        Text("preferences_appearance_events_value_as_underlined".loco()).tag(TentativeEventsAppereance.show_underlined)
                        Text("preferences_appearance_events_value_as_inactive".loco()).tag(TentativeEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco()).tag(TentativeEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_events_declined_title".loco()) {
                    Picker("", selection: $declinedEventsAppereance) {
                        Text("preferences_appearance_events_value_with_strikethrough".loco())
                            .tag(DeclinedEventsAppereance.strikethrough)
                        Text("preferences_appearance_events_value_as_inactive".loco()).tag(DeclinedEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco()).tag(DeclinedEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_events_past_title".loco()) {
                    Picker("", selection: $pastEventsAppereance) {
                        Text("preferences_appearance_events_value_show".loco()).tag(PastEventsAppereance.show_active)
                        Text("preferences_appearance_events_value_as_inactive".loco()).tag(PastEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco()).tag(PastEventsAppereance.hide)
                    }
                    .labelsHidden()
                }
            }
            .padding(.bottom, 12)
        }
    }
}

struct StatusBarSection: View {
    @Default(.eventTitleIconFormat) var eventTitleIconFormat
    @Default(.eventTitleFormat) var eventTitleFormat
    @Default(.eventTimeFormat) var eventTimeFormat
    @Default(.statusbarEventTitleLength) var statusbarEventTitleLength
    @Default(.showEventMaxTimeUntilEventThreshold) var showEventMaxTimeUntilEventThreshold
    @Default(.showEventMaxTimeUntilEventEnabled) var showEventMaxTimeUntilEventEnabled
    @Default(.ongoingEventVisibility) var ongoingEventVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Status bar", systemImage: "menubar.rectangle")

            VStack(alignment: .leading, spacing: 10) {
                SettingsRow("preferences_appearance_status_bar_icon_title".loco()) {
                    Picker("", selection: $eventTitleIconFormat) {
                        Text("preferences_appearance_status_bar_icon_calendar_icon_value".loco())
                            .tag(EventTitleIconFormat.calendar)
                        Text("preferences_appearance_status_bar_icon_app_icon_value".loco())
                            .tag(EventTitleIconFormat.appicon)
                        Text("preferences_appearance_status_bar_icon_specific_icon_value".loco())
                            .tag(EventTitleIconFormat.eventtype)
                        Text("preferences_appearance_status_bar_icon_no_icon_value".loco())
                            .tag(EventTitleIconFormat.none)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_status_bar_title_title".loco()) {
                    Picker("", selection: $eventTitleFormat) {
                        Text("preferences_appearance_status_bar_title_event_title_value".loco()).tag(EventTitleFormat.show)
                        Text("preferences_appearance_status_bar_title_dot_value".loco()).tag(EventTitleFormat.dot)
                        Text("preferences_appearance_status_bar_title_hide_value".loco()).tag(EventTitleFormat.none)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_status_bar_time_format_title".loco()) {
                    Picker("", selection: $eventTimeFormat) {
                        Text("preferences_appearance_menu_time_format_12_hour_value".loco()).tag(TimeFormat.am_pm)
                        Text("preferences_appearance_menu_time_format_24_hour_value".loco()).tag(TimeFormat.military)
                    }
                    .labelsHidden()
                }

                SettingsRow("preferences_appearance_status_bar_ongoing_title".loco()) {
                    Picker("", selection: $ongoingEventVisibility) {
                        Text("preferences_appearance_status_bar_ongoing_time_immediate_value".loco())
                            .tag(OngoingEventVisibility.hideImmediateAfter)
                        Text("preferences_appearance_status_bar_ongoing_time_ten_after_value".loco())
                            .tag(OngoingEventVisibility.showTenMinAfter)
                        Text("preferences_appearance_status_bar_ongoing_time_ten_before_next_value".loco())
                            .tag(OngoingEventVisibility.showTenMinBeforeNext)
                    }
                    .labelsHidden()
                }
            }
            .padding(.bottom, 12)
        }
    }
}

struct MenuSection: View {
    @Default(.timeFormat) var timeFormat
    @Default(.shortenEventTitle) var shortenEventTitle
    @Default(.menuEventTitleLength) var menuEventTitleLength
    @Default(.showEventEndTime) var showEventEndTime
    @Default(.showEventDetails) var showEventDetails
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon
    @Default(.showTimelineInMenu) var showTimelineInMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Menu", systemImage: "filemenu.and.selection")

            VStack(alignment: .leading, spacing: 10) {
                SettingsRow("preferences_appearance_menu_show_timeline_toggle".loco()) {
                    Toggle("", isOn: $showTimelineInMenu).labelsHidden()
                }

                SettingsRow("preferences_appearance_menu_shorten_event_title_toggle".loco()) {
                    Toggle("", isOn: $shortenEventTitle).labelsHidden()
                }

                SettingsRow("preferences_appearance_menu_show_event_end_time_value".loco()) {
                    Toggle("", isOn: $showEventEndTime).labelsHidden()
                }

                SettingsRow("preferences_appearance_menu_show_meeting_service_icon".loco()) {
                    Toggle("", isOn: $showMeetingServiceIcon).labelsHidden()
                }

                SettingsRow("preferences_appearance_menu_show_event_details".loco()) {
                    Toggle("", isOn: $showEventDetails).labelsHidden()
                }
            }
        }
    }
}

#Preview {
    AppearanceTab().padding().frame(width: 700, height: 620)
}
