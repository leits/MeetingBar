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
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .frame(width: 210, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AppearanceTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            EventsSection()
            StatusBarSection()
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
        GroupBox(
            label: Label(
                "preferences_appearance_events_title".loco(),
                systemImage: "calendar.day.timeline.left")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow("preferences_appearance_events_show_events_for_title".loco()) {
                    Picker("", selection: $showEventsForPeriod) {
                        Text("preferences_appearance_events_show_events_for_today_value".loco())
                            .tag(ShowEventsForPeriod.today)
                        Text(
                            "preferences_appearance_events_show_events_for_today_tomorrow_value"
                                .loco()
                        )
                        .tag(ShowEventsForPeriod.today_n_tomorrow)
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                SettingsRow("preferences_appearance_events_all_day_title".loco()) {
                    Picker("", selection: $allDayEvents) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(AlldayEventsAppereance.show)
                        Text("preferences_appearance_events_value_only_with_link".loco())
                            .tag(AlldayEventsAppereance.show_with_meeting_link_only)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(AlldayEventsAppereance.hide)
                    }
                    .labelsHidden()
                    .frame(width: 320)
                }

                SettingsRow("preferences_appearance_events_non_all_day_title".loco()) {
                    Picker("", selection: $nonAllDayEvents) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(NonAlldayEventsAppereance.show)
                        Text(
                            "preferences_appearance_events_value_inactive_without_meeting_link"
                                .loco()
                        )
                        .tag(NonAlldayEventsAppereance.show_inactive_without_meeting_link)
                        Text(
                            "preferences_appearance_events_value_hide_without_meeting_link".loco()
                        )
                        .tag(NonAlldayEventsAppereance.hide_without_meeting_link)
                    }
                    .labelsHidden()
                    .frame(width: 320)
                }

                SettingsRow("preferences_appearance_events_without_guest_title".loco()) {
                    Picker("", selection: $personalEventsAppereance) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(PastEventsAppereance.show_active)
                        Text("preferences_appearance_events_value_as_inactive".loco())
                            .tag(PastEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(PastEventsAppereance.hide)
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                SettingsRow("preferences_appearance_events_pending_title".loco()) {
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
                    .frame(width: 280)
                }

                SettingsRow("preferences_appearance_events_tentative_title".loco()) {
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
                    .frame(width: 280)
                }

                SettingsRow("preferences_appearance_events_declined_title".loco()) {
                    Picker("", selection: $declinedEventsAppereance) {
                        Text("preferences_appearance_events_value_with_strikethrough".loco())
                            .tag(DeclinedEventsAppereance.strikethrough)
                        Text("preferences_appearance_events_value_as_inactive".loco())
                            .tag(DeclinedEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(DeclinedEventsAppereance.hide)
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                SettingsRow("preferences_appearance_events_past_title".loco()) {
                    Picker("", selection: $pastEventsAppereance) {
                        Text("preferences_appearance_events_value_show".loco())
                            .tag(PastEventsAppereance.show_active)
                        Text("preferences_appearance_events_value_as_inactive".loco())
                            .tag(PastEventsAppereance.show_inactive)
                        Text("preferences_appearance_events_value_hide".loco())
                            .tag(PastEventsAppereance.hide)
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }
            }
            .padding(8)
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
        GroupBox(
            label: Label(
                "preferences_appearance_status_bar_title".loco(),
                systemImage: "menubar.rectangle")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow("preferences_appearance_status_bar_icon_title".loco()) {
                    Picker("", selection: $eventTitleIconFormat) {
                        HStack {
                            Image(nsImage: getImage(iconName: EventTitleIconFormat.calendar.rawValue))
                                .resizable()
                                .frame(width: 16.0, height: 16.0)
                            Text("preferences_appearance_status_bar_icon_calendar_icon_value".loco())
                        }.tag(EventTitleIconFormat.calendar)

                        HStack {
                            Image(nsImage: getImage(iconName: EventTitleIconFormat.appicon.rawValue))
                                .resizable()
                                .frame(width: 16.0, height: 16.0)
                            Text("preferences_appearance_status_bar_icon_app_icon_value".loco())
                        }.tag(EventTitleIconFormat.appicon)

                        HStack {
                            Image(nsImage: getImage(iconName: EventTitleIconFormat.eventtype.rawValue))
                                .resizable()
                                .frame(width: 16.0, height: 16.0)
                            Text("preferences_appearance_status_bar_icon_specific_icon_value".loco())
                        }.tag(EventTitleIconFormat.eventtype)

                        HStack {
                            Image(nsImage: getImage(iconName: EventTitleIconFormat.none.rawValue))
                                .resizable()
                                .frame(width: 16.0, height: 16.0)
                            Text("preferences_appearance_status_bar_icon_no_icon_value".loco())
                        }.tag(EventTitleIconFormat.none)
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                SettingsRow("preferences_appearance_status_bar_title_title".loco()) {
                    Picker("", selection: $eventTitleFormat) {
                        Text("preferences_appearance_status_bar_title_event_title_value".loco()).tag(
                            EventTitleFormat.show)
                        Text("preferences_appearance_status_bar_title_dot_value".loco()).tag(
                            EventTitleFormat.dot)
                        Text("preferences_appearance_status_bar_title_hide_value".loco()).tag(
                            EventTitleFormat.none)
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                SettingsRow(
                    "preferences_appearance_status_bar_title_shorten_stepper".loco(
                        statusbarEventTitleLength)
                ) {
                    Stepper(
                        "",
                        value: $statusbarEventTitleLength,
                        in: statusbarEventTitleLengthLimits.min
                            ... statusbarEventTitleLengthLimits.max,
                        step: 5
                    )
                    .labelsHidden()
                    .disabled(eventTitleFormat != .show)
                }

                SettingsRow("preferences_appearance_status_bar_time_title".loco()) {
                    Picker("", selection: $eventTimeFormat) {
                        ForEach(
                            PreferencesStatusBarTimeOption.allCases,
                            id: \.format
                        ) { option in
                            Text(option.titleKey.loco()).tag(option.format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                SettingsRow("preferences_appearance_status_bar_next_event_toggle".loco()) {
                    HStack {
                        Toggle("", isOn: $showEventMaxTimeUntilEventEnabled)
                            .labelsHidden()
                        Stepper(
                            "preferences_appearance_status_bar_next_event_stepper".loco(
                                showEventMaxTimeUntilEventThreshold),
                            value: $showEventMaxTimeUntilEventThreshold,
                            in: 5 ... 720,
                            step: 5
                        )
                        .disabled(!showEventMaxTimeUntilEventEnabled)
                    }
                }

                SettingsRow("preferences_appearance_status_bar_ongoing_title".loco()) {
                    Picker("", selection: $ongoingEventVisibility) {
                        Text(
                            "preferences_appearance_status_bar_ongoing_time_immediate_value".loco()
                        )
                        .tag(OngoingEventVisibility.hideImmediateAfter)
                        Text(
                            "preferences_appearance_status_bar_ongoing_time_ten_after_value".loco()
                        )
                        .tag(OngoingEventVisibility.showTenMinAfter)
                        Text(
                            "preferences_appearance_status_bar_ongoing_time_ten_before_next_value"
                                .loco()
                        )
                        .tag(OngoingEventVisibility.showTenMinBeforeNext)
                    }
                    .labelsHidden()
                    .frame(minWidth: 340, idealWidth: 380)
                }
            }
            .padding(8)
        }
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
    @Default(.showTimelineInMenu) var showTimelineInMenu

    var body: some View {
        GroupBox(
            label: Label(
                "preferences_section_menu_title".loco(),
                systemImage: "filemenu.and.selection")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow("preferences_appearance_menu_show_timeline_toggle".loco()) {
                    Toggle("", isOn: $showTimelineInMenu)
                        .labelsHidden()
                }

                SettingsRow("preferences_appearance_menu_shorten_event_title_toggle".loco()) {
                    HStack {
                        Toggle("", isOn: $shortenEventTitle)
                            .labelsHidden()
                        Stepper(
                            "preferences_appearance_menu_shorten_event_title_stepper".loco(
                                menuEventTitleLength),
                            value: $menuEventTitleLength,
                            in: 20 ... 100,
                            step: 5
                        )
                        .disabled(!shortenEventTitle)
                    }
                }

                SettingsRow("preferences_appearance_menu_time_format_title".loco()) {
                    Picker("", selection: $timeFormat) {
                        Text("preferences_appearance_menu_time_format_12_hour_value".loco())
                            .tag(TimeFormat.am_pm)
                        Text("preferences_appearance_menu_time_format_24_hour_value".loco())
                            .tag(TimeFormat.military)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                SettingsRow("preferences_appearance_menu_show_event_end_time_value".loco()) {
                    Toggle("", isOn: $showEventEndTime)
                        .labelsHidden()
                }
                SettingsRow("preferences_appearance_menu_show_event_icon_value".loco()) {
                    Toggle("", isOn: $showMeetingServiceIcon)
                        .labelsHidden()
                }
                SettingsRow("preferences_appearance_menu_show_event_details_value".loco()) {
                    Toggle("", isOn: $showEventDetails)
                        .labelsHidden()
                }
            }
            .padding(8)
        }
    }
}

#Preview {
    AppearanceTab().padding().frame(width: 700, height: 620)
}
