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
    @Default(.meetBrowser) var meetBrowser
    @Default(.browserForCreateMeeting) var browserForCreateMeeting
    @Default(.defaultBrowser) var defaultBrowser
    @Default(.useAppForZoomLinks) var useAppForZoomLinks
    @Default(.useAppForTeamsLinks) var useAppForTeamsLinks
    @Default(.useAppForJitsiLinks) var useAppForJitsiLinks
    @Default(.createMeetingServiceUrl) var createMeetingServiceUrl
    @Default(.createMeetingService) var createMeetingService
    @Default(.browsers) var allBrowser

    @State var showBrowserConfiguration = false

    var body: some View {
        VStack {
            Section {
                Picker(selection: $defaultBrowser, label: Text("preferences_services_link_meeting_title".loco()).frame(width: 200, alignment: .leading)) {
                    Text(systemDefaultBrowser.name).tag(systemDefaultBrowser)
                    ForEach(allBrowser, id: \.self) { (browser: Browser) in
                        Text(browser.name).tag(browser)
                    }
                }

                Picker(selection: $meetBrowser, label: Text("preferences_services_link_meet_title".loco()).frame(width: 200, alignment: .leading)) {
                    Text(systemDefaultBrowser.name).tag(systemDefaultBrowser)
                    Text(MeetInOneBrowser.name).tag(MeetInOneBrowser)
                    ForEach(allBrowser, id: \.self) { (browser: Browser) in
                        Text(browser.name).tag(browser)
                    }
                }

                Picker(selection: $useAppForZoomLinks, label: Text("preferences_services_link_zoom_title".loco()).frame(width: 200, alignment: .leading)) {
                    Text("preferences_services_link_default_browser_value".loco()).tag(false)
                    Text("preferences_services_link_zoom_value".loco()).tag(true)
                }
                Picker(selection: $useAppForTeamsLinks, label: Text("preferences_services_link_team_title".loco()).frame(width: 200, alignment: .leading)) {
                    Text("preferences_services_link_default_browser_value".loco()).tag(false)
                    Text("preferences_services_link_teams_value".loco()).tag(true)
                }
                Picker(selection: $useAppForJitsiLinks, label: Text("preferences_services_link_jitsi_title".loco()).frame(width: 200, alignment: .leading)) {
                    Text("preferences_services_link_default_browser_value".loco()).tag(false)
                    Text("preferences_services_link_jitsi_value".loco()).tag(true)
                }
            }.padding(.horizontal, 10)

            Section {
                // Move other to end of list
                let services = MeetingServices.allCases.sorted { lhs, rhs in
                    if lhs == .other {
                        return false
                    }
                    if rhs == .other {
                        return true
                    }
                    return lhs.localizedValue < rhs.localizedValue
                }
                .map(\.localizedValue)
                .joined(separator: ", ")

                Text("preferences_services_supported_links_list".loco(services))
                HStack {
                    Text("preferences_services_supported_links_mailback".loco())
                    Button("✉️") {
                        Links.emailMe.openInDefaultBrowser()
                    }
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
                HStack {
                    Picker(selection: $browserForCreateMeeting, label: Text("preferences_services_create_meeting_browser_title".loco()).frame(width: 150, alignment: .leading)) {
                        Text(systemDefaultBrowser.name).tag(systemDefaultBrowser)
                        ForEach(allBrowser, id: \.self) { (browser: Browser) in
                            Text(browser.name).tag(browser)
                        }
                    }
                }.padding(.horizontal, 10)
            }.padding()

            Divider()

            VStack {
                Button(action: clickConfigureBrowser) {
                    Text("preferences_configure_browsers_button".loco())
                }.sheet(isPresented: $showBrowserConfiguration) {
                    BrowserConfigView()
                }
            }.padding()
            Spacer()
        }.padding()
    }

    func clickConfigureBrowser() {
        showBrowserConfiguration.toggle()
    }
}

struct CreateMeetingServicePicker: View {
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        Picker(selection: $createMeetingService, label: Text("")) {
            Text(CreateMeetingServices.meet.localizedValue).tag(CreateMeetingServices.meet)
            Text(CreateMeetingServices.zoom.localizedValue).tag(CreateMeetingServices.zoom)
            Text(CreateMeetingServices.teams.localizedValue).tag(CreateMeetingServices.teams)
            Text(CreateMeetingServices.jam.localizedValue).tag(CreateMeetingServices.jam)
            Text(CreateMeetingServices.coscreen.localizedValue).tag(CreateMeetingServices.coscreen)
            Text(CreateMeetingServices.gcalendar.localizedValue).tag(CreateMeetingServices.gcalendar)
            Text(CreateMeetingServices.outlook_live.localizedValue).tag(CreateMeetingServices.outlook_live)
            Text(CreateMeetingServices.outlook_office365.localizedValue).tag(CreateMeetingServices.outlook_office365)
            Text(CreateMeetingServices.url.localizedValue).tag(CreateMeetingServices.url)
        }.labelsHidden()
    }
}
