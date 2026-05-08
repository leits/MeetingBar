//
//  LinksTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

struct LinksTab: View {
    @Default(.providerBrowsers) var providerBrowsers
    @Default(.browserForCreateMeeting) var browserForCreateMeeting
    @Default(.defaultBrowser) var defaultBrowser
    @Default(.createMeetingServiceUrl) var createMeetingServiceUrl
    @Default(.createMeetingService) var createMeetingService
    @Default(.browsers) var allBrowser

    @Default(.bookmarks) var bookmarks

    @State var showBrowserConfiguration = false

    @State var showingAddBookmarkModal = false
    @State private var showingAlert = false
    @State private var bookmark: Bookmark?

    /// Returns a Binding<Browser> for a specific meeting provider ID.
    /// Selection of `systemDefaultBrowser` removes the key from the map (fall through to default).
    private func providerBrowserBinding(forID id: String) -> Binding<Browser> {
        Binding<Browser>(
            get: { providerBrowsers[id] ?? systemDefaultBrowser },
            set: { newBrowser in
                if newBrowser == systemDefaultBrowser {
                    providerBrowsers.removeValue(forKey: id)
                } else {
                    providerBrowsers[id] = newBrowser
                }
            }
        )
    }

    var body: some View {
        VStack {
            GroupBox(label: Label("preferences_section_open_title".loco(), systemImage: "link")) {
                Picker(
                    selection: $defaultBrowser,
                    label: Text("preferences_services_link_meeting_title".loco()).frame(
                        width: 200, alignment: .leading)
                ) {
                    Text(systemDefaultBrowser.name).tag(systemDefaultBrowser)
                    ForEach(allBrowser, id: \.self) { (browser: Browser) in
                        Text(browser.name).tag(browser)
                    }
                }

                ForEach(
                    MeetingProvider.all.filter { $0.nativeAppBrowserName != nil }, id: \.id
                ) { provider in
                    let nativeBrowser = Browser(name: provider.nativeAppBrowserName!, path: "")
                    Picker(
                        selection: providerBrowserBinding(forID: provider.id),
                        label: Text(
                            "preferences_services_link_service_title".loco(provider.displayName)
                        )
                        .frame(width: 200, alignment: .leading)
                    ) {
                        Text(systemDefaultBrowser.name).tag(systemDefaultBrowser)
                        Text(nativeBrowser.name).tag(nativeBrowser)
                        ForEach(allBrowser, id: \.self) { (browser: Browser) in
                            Text(browser.name).tag(browser)
                        }
                    }
                }
            }

            GroupBox(
                label: Label("preferences_section_create_title".loco(), systemImage: "plus.circle")
            ) {
                HStack {
                    Text("preferences_services_create_meeting_title".loco()).frame(
                        width: 150, alignment: .leading)
                    CreateMeetingServicePicker()
                }

                if createMeetingService == CreateMeetingServices.url {
                    HStack {
                        Text("preferences_services_create_meeting_custom_url_value".loco()).frame(
                            width: 150, alignment: .leading)
                        TextField(
                            "preferences_services_create_meeting_custom_url_placeholder".loco(),
                            text: $createMeetingServiceUrl
                        ).textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    HStack {
                        Text("preferences_services_google_meet_tip".loco()).foregroundColor(.gray)
                            .font(.system(size: 12))
                    }
                }
                Picker(
                    selection: $browserForCreateMeeting,
                    label: Text("preferences_services_create_meeting_browser_title".loco())
                        .frame(width: 150, alignment: .leading)
                ) {
                    Text(systemDefaultBrowser.name).tag(systemDefaultBrowser)
                    ForEach(allBrowser, id: \.self) { (browser: Browser) in
                        Text(browser.name).tag(browser)
                    }
                }
            }

            HStack {
                Spacer()
                Button(action: clickConfigureBrowser) {
                    Text("preferences_configure_browsers_button".loco())
                }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $showBrowserConfiguration) {
                    BrowserConfigView()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)

            GroupBox(label: Label("preferences_tab_bookmarks".loco(), systemImage: "bookmark")) {
                List {
                    if self.bookmarks.isEmpty {
                        Text("preferences_bookmarks_no_bookmarks_placeholder".loco())
                    }
                    ForEach(bookmarks, id: \.self) { bookmark in
                        HStack {
                            Image(nsImage: NSImage(named: NSImage.listViewTemplateName)!)
                                .foregroundColor(.gray)

                            Text("\(bookmark.name) (\(bookmark.service)): \(bookmark.url)")
                            Spacer()
                            Button(action: {
                                self.bookmark = bookmark
                                self.showingAlert = true
                            }) {
                                Image(
                                    nsImage: NSImage(
                                        named: NSImage.stopProgressFreestandingTemplateName)!)
                            }.buttonStyle(PlainButtonStyle())
                        }.padding(3)
                    }.onMove { source, destination in
                        bookmarks.move(fromOffsets: source, toOffset: destination)
                    }
                    Button("preferences_bookmarks_add_bookmark_button".loco()) {
                        self.showingAddBookmarkModal.toggle()
                    }.sheet(isPresented: $showingAddBookmarkModal) {
                        AddBookmarkModal()
                    }
                }.listStyle(.sidebar)
                    .alert(isPresented: $showingAlert) {
                        Alert(
                            title: Text("preferences_bookmarks_delete_bookmark_title".loco()),
                            message: Text(
                                "preferences_bookmarks_delete_bookmark_message".loco(
                                    self.bookmark?.name ?? "")),
                            primaryButton: .default(Text("general_delete".loco())) {
                                bookmarks.removeAll { $0.url == self.bookmark?.url }
                            },
                            secondaryButton: .cancel()
                        )
                    }
            }
            Spacer()
        }
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
            Text(CreateMeetingServices.gcalendar.localizedValue).tag(
                CreateMeetingServices.gcalendar)
            Text(CreateMeetingServices.outlook_live.localizedValue).tag(
                CreateMeetingServices.outlook_live)
            Text(CreateMeetingServices.outlook_office365.localizedValue).tag(
                CreateMeetingServices.outlook_office365)
            Text(CreateMeetingServices.url.localizedValue).tag(CreateMeetingServices.url)
        }.labelsHidden()
    }
}

struct AddBookmarkModal: View {
    @Environment(\.presentationMode) var presentationMode

    @Default(.bookmarks) var bookmarks

    @State private var showingAlert = false
    @State private var error_msg = ""

    @State var name: String = ""
    @State var url: String = ""
    @State var service = MeetingServices.meet

    var body: some View {
        VStack {
            HStack {
                Text("preferences_bookmarks_new_bookmark_title".loco()).font(.headline)
            }
            Spacer()
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 15
                ) {
                    Text("preferences_bookmarks_new_bookmark_name".loco())
                    Text("preferences_bookmarks_new_bookmark_link_phone".loco())
                    Text("preferences_bookmarks_new_bookmark_service".loco())
                }
                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    TextField("", text: $name)
                    TextField("", text: $url)
                    Picker(selection: $service, label: Text("")) {
                        Text(MeetingServices.teams.localizedValue).tag(MeetingServices.teams)
                        Text(MeetingServices.zoom.localizedValue).tag(MeetingServices.zoom)
                        Text(MeetingServices.meet.localizedValue).tag(MeetingServices.meet)
                        Text(MeetingServices.facetime.localizedValue).tag(MeetingServices.facetime)
                        Text(MeetingServices.facetimeaudio.localizedValue).tag(
                            MeetingServices.facetimeaudio)
                        Text(MeetingServices.phone.localizedValue).tag(MeetingServices.phone)
                        Text(MeetingServices.other.localizedValue).tag(MeetingServices.other)
                    }.labelsHidden()
                }
            }
            Spacer()
            HStack {
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("general_cancel".loco())
                }
                Button(action: {
                    if let bookmark = bookmarks.first(where: { $0.url.absoluteString == url }) {
                        error_msg = "preferences_bookmarks_new_bookmark_already_exist".loco(
                            bookmark.name, url)
                        showingAlert = true
                    } else {
                        self.presentationMode.wrappedValue.dismiss()
                        guard let bookmarkURL = URL(string: url) else {
                            error_msg = "preferences_services_create_meeting_custom_url_placeholder"
                                .loco()
                            showingAlert = true
                            return
                        }
                        let bookmark = Bookmark(
                            name: name, service: service.rawValue, url: bookmarkURL)
                        bookmarks.append(bookmark)
                    }
                }) {
                    Text("general_add".loco())
                }.disabled(url.isEmpty || name.isEmpty)
            }
        }.frame(width: 500, height: 200)
            .padding()
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("preferences_bookmarks_new_bookmark_error_title".loco()),
                    message: Text(error_msg), dismissButton: .default(Text("general_ok".loco())))
            }
    }
}

#Preview {
    LinksTab().padding().frame(width: 700, height: 620)
}
