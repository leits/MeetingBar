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
    @Default(.useChromeForMeetLinks) var useChromeForMeetLinks
    @Default(.useChromeForHangoutsLinks) var useChromeForHangoutsLinks
    @Default(.useAppForZoomLinks) var useAppForZoomLinks
    @Default(.useAppForTeamsLinks) var useAppForTeamsLinks

    var body: some View {
        VStack {
            Section {
                Picker(selection: $useChromeForMeetLinks, label: Text("Open Meet links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(ChromeExecutable.defaultBrowser)
                    Text("Chrome").tag(ChromeExecutable.chrome)
                    Text("Chromium").tag(ChromeExecutable.chromium)
                }
                Picker(selection: $useAppForZoomLinks, label: Text("Open Zoom links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Zoom app").tag(true)
                }
                Picker(selection: $useAppForTeamsLinks, label: Text("Open Teams links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Teams app").tag(true)
                }
            }.padding(.horizontal, 10)
            Section {
                Text("Supported links for services:\n\(MeetingServices.allCases.map { $0.rawValue }.joined(separator: ", "))")
                HStack {
                    Text("If the service you use isn't supported, email me")
                    Button("✉️", action: emailMe)
                }
            }.foregroundColor(.gray).font(.system(size: 12)).padding(.horizontal, 10)
            Divider()
            HStack {
                Text("Create meetings in").frame(width: 150, alignment: .leading)
                CreateMeetingServicePicker()
            }.padding(.horizontal, 10)
            Spacer()
        }.padding()
    }
}

struct CreateMeetingServicePicker: View {
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        Picker(selection: $createMeetingService, label: Text("")) {
            Text(CreateMeetingServices.meet.rawValue).tag(CreateMeetingServices.meet)
            Text(CreateMeetingServices.zoom.rawValue).tag(CreateMeetingServices.zoom)
            Text(CreateMeetingServices.teams.rawValue).tag(CreateMeetingServices.teams)
            Text(CreateMeetingServices.hangouts.rawValue).tag(CreateMeetingServices.hangouts)
            Text(CreateMeetingServices.gcalendar.rawValue).tag(CreateMeetingServices.gcalendar)
            Text(CreateMeetingServices.outlook_live.rawValue).tag(CreateMeetingServices.outlook_live)
            Text(CreateMeetingServices.outlook_office365.rawValue).tag(CreateMeetingServices.outlook_office365)
        }.labelsHidden()
    }
}
