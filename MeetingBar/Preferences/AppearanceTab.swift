//
//  AppearanceTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

// MARK: - Consistent Row Layout

private struct PreferenceRow<Control: View>: View {
    let label: String
    let control: Control
    let description: String?

    init(
        _ label: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.description = description
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 16) {
                Text(label)
                    .font(.system(size: 13))
                    .frame(width: 220, alignment: .leading)

                control
                    .frame(minWidth: 280, alignment: .leading)

                Spacer()
            }
            .frame(height: 26)

            if let description = description {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 220 + 16)
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String?
    let description: String?

    init(_ title: String, icon: String? = nil, description: String? = nil) {
        self.title = title
        self.icon = icon
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            if let description = description {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Main Tab

struct AppearanceTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EventsSection()
                Divider().padding(.vertical, 16)
                StatusBarSection()
                Divider().padding(.vertical, 16)
                MenuSection()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}

// MARK: - Events Section

struct EventsSection: View {
    @Default(.showEventsForPeriod) var showEventsForPeriod
    @Default(.allDayEvents) var allDayEvents
    @Default(.nonAllDayEvents) var nonAllDayEvents
    @Default(.personalEventsAppereance) var personalEventsAppereance
    @Default(.showPendingEvents) var showPendingEvents
    @Default(.showTentativeEvents) var showTentativeEvents
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.pastEventsAppereance) var pastEventsAppereance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Events", icon: "calendar.day.timeline.left")

            VStack(alignment: .leading, spacing: 12) {
                // Group 1: Range
                PreferenceRow("Show events for") {
                    Picker("", selection: $showEventsForPeriod) {
                        Text("preferences_appearance_events_show_events_for_today_value".loco())
                            .tag(ShowEventsForPeriod.today)
                        Text("preferences_appearance_events_show_events_for_today_tomorrow_value".loco())
                            .tag(ShowEventsForPeriod.today_n_tomorrow)
                    }
                    .labelsHidden()
                }

                Divider().padding(.vertical, 4)

                // Group 2: Event types
                PreferenceRow("preferences_appearance_events_all_day_title".loco()) {
                    Picker("", selection: $allDayEvents) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(AlldayEventsAppereance.show)
                        Text("preferences_appearance_events_value_only_with_link".loco())
                            .tag(AlldayEventsAppereance.show_with_meeting_link_only)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(AlldayEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                PreferenceRow("preferences_appearance_events_non_all_day_title".loco()) {
                    Picker("", selection: $nonAllDayEvents) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(NonAlldayEventsAppereance.show)
                        Text("preferences_appearance_events_value_inactive_without_meeting_link".loco())
                            .tag(NonAlldayEventsAppereance.show_inactive_without_meeting_link)
                        Text("preferences_appearance_events_value_hide_without_meeting_link".loco())
                            .tag(NonAlldayEventsAppereance.hide_without_meeting_link)
                    }
                    .labelsHidden()
                }

                PreferenceRow("preferences_appearance_events_without_guest_title".loco()) {
                    Picker("", selection: $personalEventsAppereance) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(PastEventsAppereance.show_active)
                        Text("preferences_appearance_events_value_as_inactive".loco())
                            .tag(PastEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(PastEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                Divider().padding(.vertical, 4)

                // Group 3: Invitation status
                PreferenceRow("preferences_appearance_events_pending_title".loco()) {
                    Picker("", selection: $showPendingEvents) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(PendingEventsAppereance.show)
                        Text("preferences_appearance_events_value_as_underlined".loco())
                            .tag(PendingEventsAppereance.show_underlined)
                        Text("preferences_appearance_events_value_as_inactive".loco())
                            .tag(PendingEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(PendingEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                PreferenceRow("preferences_appearance_events_tentative_title".loco()) {
                    Picker("", selection: $showTentativeEvents) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(TentativeEventsAppereance.show)
                        Text("preferences_appearance_events_value_as_underlined".loco())
                            .tag(TentativeEventsAppereance.show_underlined)
                        Text("preferences_appearance_events_value_as_inactive".loco())
                            .tag(TentativeEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(TentativeEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                PreferenceRow("preferences_appearance_events_declined_title".loco()) {
                    Picker("", selection: $declinedEventsAppereance) {
                        Text("preferences_appearance_events_value_with_strikethrough".loco())
                            .tag(DeclinedEventsAppereance.strikethrough)
                        Text("preferences_appearance_events_value_as_inactive".loco())
                            .tag(DeclinedEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(DeclinedEventsAppereance.hide)
                    }
                    .labelsHidden()
                }

                Divider().padding(.vertical, 4)

                // Group 4: Time
                PreferenceRow("preferences_appearance_events_past_title".loco()) {
                    Picker("", selection: $pastEventsAppereance) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(PastEventsAppereance.show_active)
                        Text("preferences_appearance_events_value_as_inactive".loco())
                            .tag(PastEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(PastEventsAppereance.hide)
                    }
                    .labelsHidden()
                }
            }
        }
    }
}

// MARK: - Status Bar Section

struct StatusBarSection: View {
    @Default(.eventTitleIconFormat) var eventTitleIconFormat
    @Default(.eventTitleFormat) var eventTitleFormat
    @Default(.eventTimeFormat) var eventTimeFormat
    @Default(.ongoingEventVisibility) var ongoingEventVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Status Bar", icon: "menubar.rectangle")

            VStack(alignment: .leading, spacing: 12) {
                PreferenceRow("Icon") {
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

                PreferenceRow("Title") {
                    Picker("", selection: $eventTitleFormat) {
                        Text("preferences_appearance_status_bar_title_event_title_value".loco())
                            .tag(EventTitleFormat.show)
                        Text("preferences_appearance_status_bar_title_dot_value".loco())
                            .tag(EventTitleFormat.dot)
                        Text("preferences_appearance_status_bar_title_hide_value".loco())
                            .tag(EventTitleFormat.none)
                    }
                    .labelsHidden()
                }

                PreferenceRow("Time") {
                    Picker("", selection: $eventTimeFormat) {
                        Text("preferences_appearance_menu_time_format_12_hour_value".loco())
                            .tag(TimeFormat.am_pm)
                        Text("preferences_appearance_menu_time_format_24_hour_value".loco())
                            .tag(TimeFormat.military)
                    }
                    .labelsHidden()
                }

                Divider().padding(.vertical, 4)

                PreferenceRow("Keep ongoing event visible") {
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
        }
    }
}

// MARK: - Menu Section

struct MenuSection: View {
    @Default(.showTimelineInMenu) var showTimelineInMenu
    @Default(.showEventEndTime) var showEventEndTime
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon
    @Default(.showEventDetails) var showEventDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Menu", icon: "filemenu.and.selection")

            VStack(alignment: .leading, spacing: 12) {
                PreferenceRow("Show visual timeline") {
                    Toggle("", isOn: $showTimelineInMenu).labelsHidden()
                }

                Divider().padding(.vertical, 4)

                PreferenceRow("Show event end time") {
                    Toggle("", isOn: $showEventEndTime).labelsHidden()
                }

                PreferenceRow("Show meeting service icon") {
                    Toggle("", isOn: $showMeetingServiceIcon).labelsHidden()
                }

                PreferenceRow("Show event details as submenu") {
                    Toggle("", isOn: $showEventDetails).labelsHidden()
                }
            }
        }
    }
}

#Preview {
    AppearanceTab().frame(width: 700, height: 620)
}
