//
//  ServicesTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults

var systemDefaultBrowser = Browser(name: "Default Browser", path: "")

struct ServicesTab: View {
    @Default(.browserForMeetLinks) var browserForMeetLinks
    @Default(.browserForCreateMeeting) var browserForCreateMeeting
    @Default(.defaultBrowser) var defaultBrowser
    @Default(.useAppForZoomLinks) var useAppForZoomLinks
    @Default(.useAppForTeamsLinks) var useAppForTeamsLinks
    @Default(.createMeetingServiceUrl) var createMeetingServiceUrl
    @Default(.createMeetingService) var createMeetingService
    @Default(.browser) var allBrowser

    @State var showBrowserConfiguration = false

    var body: some View {
        VStack {
            Section {
                Picker(selection: $defaultBrowser, label: Text("Open meeting links in").frame(width: 160, alignment: .leading)) {
                    Text(systemDefaultBrowser.name).tag(systemDefaultBrowser)
                    ForEach(allBrowser, id: \.self) { (browser: Browser) in
                        Text(browser.name).tag(browser)
                    }
                }

                Picker(selection: $browserForMeetLinks, label: Text("Open Google Meet links in").frame(width: 160, alignment: .leading)) {
                    Text(systemDefaultBrowser.name).tag(systemDefaultBrowser)
                    ForEach(allBrowser, id: \.self) { (browser: Browser) in
                        Text(browser.name).tag(browser)
                    }
                }

                Picker(selection: $useAppForZoomLinks, label: Text("Open Zoom links in").frame(width: 160, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Zoom app").tag(true)
                }

                Picker(selection: $useAppForTeamsLinks, label: Text("Open Teams links in").frame(width: 160, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Teams app").tag(true)
                }
            }.padding(.horizontal, 10)

            Section {
                Text("Supported links for services:\n\(MeetingServices.allCases.map { $0.rawValue }.joined(separator: ", "))")
                HStack {
                    Text("If the service you use isn't supported, email me")
                    Button("✉️") {
                        Links.emailMe.openInDefaultBrowser()
                    }
                }
            }.foregroundColor(.gray).font(.system(size: 12)).padding(.horizontal, 10)

            Divider()
            VStack {
                HStack {
                    Text("Create meetings via").frame(width: 150, alignment: .leading)
                    CreateMeetingServicePicker()
                }.padding(.horizontal, 10)

                if createMeetingService == CreateMeetingServices.url {
                    HStack {
                        Text("Custom url").frame(width: 150, alignment: .leading)
                        TextField("Please enter a valid url (with the url scheme, e.g. https://)", text: $createMeetingServiceUrl).textFieldStyle(RoundedBorderTextFieldStyle())
                    }.padding(.horizontal, 10)
                    HStack {
                        Text("Tip: Google Meet supports choosing account via parameter, e.g. https://meet.google.com/new?authuser=1").foregroundColor(.gray).font(.system(size: 12))
                    }
                }
                HStack {
                    Picker(selection: $browserForCreateMeeting, label: Text("Use browser").frame(width: 150, alignment: .leading)) {
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
                    Text("Configure browsers")
                }.sheet(isPresented: $showBrowserConfiguration) {
                    BrowserConfigView()
                }
            }.padding()
            Spacer()
        }.padding()
    }

    func clickConfigureBrowser() {
        self.showBrowserConfiguration.toggle()
    }
}

struct CreateMeetingServicePicker: View {
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        Picker(selection: $createMeetingService, label: Text("")) {
            Text(CreateMeetingServices.meet.rawValue).tag(CreateMeetingServices.meet)
            Text(CreateMeetingServices.zoom.rawValue).tag(CreateMeetingServices.zoom)
            Text(CreateMeetingServices.teams.rawValue).tag(CreateMeetingServices.teams)
            Text(CreateMeetingServices.jam.rawValue).tag(CreateMeetingServices.jam)
            Text(CreateMeetingServices.gcalendar.rawValue).tag(CreateMeetingServices.gcalendar)
            Text(CreateMeetingServices.outlook_live.rawValue).tag(CreateMeetingServices.outlook_live)
            Text(CreateMeetingServices.outlook_office365.rawValue).tag(CreateMeetingServices.outlook_office365)
            Text(CreateMeetingServices.url.rawValue).tag(CreateMeetingServices.url)
        }.labelsHidden()
    }
}
