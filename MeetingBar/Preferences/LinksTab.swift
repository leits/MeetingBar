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

    private var defaultBrowserOptions: [Browser] {
        BrowserPickerOptions.make(
            configured: allBrowser,
            selected: defaultBrowser
        )
    }

    private var createMeetingBrowserOptions: [Browser] {
        BrowserPickerOptions.make(
            configured: allBrowser,
            selected: browserForCreateMeeting
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(
                label: Label(
                    "preferences_meeting_opening_behavior_title".loco(),
                    systemImage: "arrow.up.right.square")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(
                        selection: $defaultBrowser,
                        label: Text("preferences_services_link_meeting_title".loco()).frame(
                            width: 200, alignment: .leading)
                    ) {
                        ForEach(defaultBrowserOptions, id: \.self) { (browser: Browser) in
                            Text(browser.name).tag(browser)
                        }
                    }

                    Text("preferences_services_link_default_help".loco())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("preferences_services_link_overrides_title".loco())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("preferences_services_link_overrides_help".loco())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("preferences_services_link_modes_help".loco())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(
                        MeetingProvider.all.filter { !$0.openingModes.isEmpty }, id: \.id
                    ) { provider in
                        MeetingProviderOpeningPicker(provider: provider)
                    }

                    Divider()

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button(
                            "preferences_configure_browsers_button".loco(),
                            action: clickConfigureBrowser
                        )
                        .sheet(isPresented: $showBrowserConfiguration) {
                            BrowserConfigView()
                        }
                        Text("preferences_configure_browsers_help".loco())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }

            GroupBox(
                label: Label("preferences_section_create_title".loco(), systemImage: "plus.circle")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("preferences_services_create_meeting_title".loco()).frame(
                            width: 150, alignment: .leading)
                        CreateMeetingServicePicker()
                    }

                    if createMeetingService == CreateMeetingServices.url {
                        HStack {
                            Text("preferences_services_create_meeting_custom_url_value".loco())
                                .frame(width: 150, alignment: .leading)
                            TextField(
                                "preferences_services_create_meeting_custom_url_placeholder".loco(),
                                text: $createMeetingServiceUrl
                            ).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        Text("preferences_services_google_meet_tip".loco())
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Picker(
                        selection: $browserForCreateMeeting,
                        label: Text("preferences_services_create_meeting_browser_title".loco())
                            .frame(width: 150, alignment: .leading)
                    ) {
                        ForEach(createMeetingBrowserOptions, id: \.self) { (browser: Browser) in
                            Text(browser.name).tag(browser)
                        }
                    }
                }
                .padding(8)
            }

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
                }
                .listStyle(.sidebar)
                .frame(minHeight: 160)
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

struct MeetingProviderOpeningPicker: View {
    let provider: MeetingProvider
    var labelWidth: CGFloat = 200

    @Default(.providerBrowsers) private var providerBrowsers
    @Default(.providerOpeningModes) private var providerOpeningModes
    @Default(.browsers) private var allBrowsers

    private var selectedValue: MeetingProviderOpeningSelection {
        MeetingProviderOpeningSelectionPolicy.selected(
            provider: provider,
            providerBrowsers: providerBrowsers,
            providerOpeningModes: providerOpeningModes
        )
    }

    private var selection: Binding<MeetingProviderOpeningSelection> {
        Binding(
            get: { selectedValue },
            set: { newSelection in
                let updated = MeetingProviderOpeningSelectionPolicy.updating(
                    provider: provider,
                    selection: newSelection,
                    providerBrowsers: providerBrowsers,
                    providerOpeningModes: providerOpeningModes
                )
                providerBrowsers = updated.providerBrowsers
                providerOpeningModes = updated.providerOpeningModes
            }
        )
    }

    private var browserOptions: [Browser] {
        let selectedBrowser: Browser
        switch selectedValue {
        case .browser(let browser):
            selectedBrowser = browser
        case .mode:
            selectedBrowser = systemDefaultBrowser
        }
        return BrowserPickerOptions.make(
            configured: allBrowsers,
            selected: selectedBrowser
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Picker(
                selection: selection,
                label: Text(
                    "preferences_services_link_service_title".loco(provider.displayName)
                )
                .frame(width: labelWidth, alignment: .leading)
            ) {
                ForEach(provider.openingModes, id: \.self) { mode in
                    Text(mode.titleKey.loco()).tag(
                        MeetingProviderOpeningSelection.mode(mode)
                    )
                }
                ForEach(browserOptions, id: \.self) { browser in
                    Text(browser.name).tag(MeetingProviderOpeningSelection.browser(browser))
                }
            }

            if case let .mode(mode) = selectedValue,
               let helpKey = mode.helpKey {
                Text(helpKey.loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, labelWidth + 8)
            }
        }
    }
}

struct CreateMeetingServicePicker: View {
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        Picker(selection: $createMeetingService, label: EmptyView()) {
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
