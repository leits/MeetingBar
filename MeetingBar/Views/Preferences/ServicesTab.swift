//
//  ServicesTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults

struct ServicesTab: View {
    @Default(.browserForMeetLinks) var browserForMeetLinks
    @Default(.useAppForZoomLinks) var useAppForZoomLinks
    @Default(.useAppForTeamsLinks) var useAppForTeamsLinks
    @Default(.createMeetingServiceUrl) var createMeetingServiceUrl
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        VStack {
            Section {
                Picker(selection: $browserForMeetLinks, label: Text("preferences_services_link_meet_title".loco()).frame(width: 150, alignment: .leading)) {
                    ForEach(Browser.allCases, id: \.self) { (browser: Browser) in
                        Text(browser.localizedValue).tag(browser)
                    }
                }
                Picker(selection: $useAppForZoomLinks, label: Text("preferences_services_link_zoom_title".loco()).frame(width: 150, alignment: .leading)) {
                    Text("preferences_services_link_default_browser_value".loco()).tag(false)
                    Text("preferences_services_link_zoom_value".loco()).tag(true)
                }
                Picker(selection: $useAppForTeamsLinks, label: Text("preferences_services_link_team_title".loco()).frame(width: 150, alignment: .leading)) {
                    Text("preferences_services_link_default_browser_value".loco()).tag(false)
                    Text("preferences_services_link_teams_value".loco()).tag(true)
                }
            }.padding(.horizontal, 10)
            Section {
                Text("preferences_services_supported_links_list".loco(MeetingServices.allCases.map { $0.localizedValue }.sorted().joined(separator: ", ")))
                HStack {
                    Text("preferences_services_supported_links_mailback".loco())
                    Button("✉️", action: emailMe)
                }
            }.foregroundColor(.gray).font(.system(size: 12)).padding(.horizontal, 10)
            Divider()
            VStack {
                HStack {
                    Text("preferences_services_create_meeting_title".loco()).frame(width: 150, alignment: .leading)
                    CreateMeetingServicePicker()
                }.padding(.horizontal, 10)

                if createMeetingService == CreateMeetingServices.url {
                    HStack {
                        Text("preferences_services_create_meeting_custom_url_value".loco()).frame(width: 150, alignment: .leading)
                        TextField("preferences_services_create_meeting_custom_url_placeholder".loco(), text: $createMeetingServiceUrl).textFieldStyle(RoundedBorderTextFieldStyle())
                    }.padding(.horizontal, 10)
                    HStack {
                        Text("preferences_services_google_meet_tip".loco()).foregroundColor(.gray).font(.system(size: 12))
                    }
                }
            }
            Spacer()
        }.padding()
    }
}

struct CreateMeetingServicePicker: View {
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        Picker(selection: $createMeetingService, label: Text("")) {
            Text(CreateMeetingServices.meet.localizedValue).tag(CreateMeetingServices.meet)
            Text(CreateMeetingServices.zoom.localizedValue).tag(CreateMeetingServices.zoom)
            Text(CreateMeetingServices.teams.localizedValue).tag(CreateMeetingServices.teams)
            Text(CreateMeetingServices.hangouts.localizedValue).tag(CreateMeetingServices.hangouts)
            Text(CreateMeetingServices.gcalendar.localizedValue).tag(CreateMeetingServices.gcalendar)
            Text(CreateMeetingServices.outlook_live.localizedValue).tag(CreateMeetingServices.outlook_live)
            Text(CreateMeetingServices.outlook_office365.localizedValue).tag(CreateMeetingServices.outlook_office365)
            Text(CreateMeetingServices.url.localizedValue).tag(CreateMeetingServices.url)
        }.labelsHidden()
    }
}
