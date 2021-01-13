//
//  BookmarksTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults
import KeyboardShortcuts

struct BookmarksTab: View {
    @Default(.bookmarkMeetingName) var bookmarkMeetingName
    @Default(.bookmarkMeetingURL) var bookmarkMeetingURL
    @Default(.bookmarkMeetingService) var bookmarkMeetingService

    @Default(.bookmarkMeetingName2) var bookmarkMeetingName2
    @Default(.bookmarkMeetingURL2) var bookmarkMeetingURL2
    @Default(.bookmarkMeetingService2) var bookmarkMeetingService2

    @Default(.bookmarkMeetingName3) var bookmarkMeetingName3
    @Default(.bookmarkMeetingURL3) var bookmarkMeetingURL3
    @Default(.bookmarkMeetingService3) var bookmarkMeetingService3

    @Default(.bookmarkMeetingName4) var bookmarkMeetingName4
    @Default(.bookmarkMeetingURL4) var bookmarkMeetingURL4
    @Default(.bookmarkMeetingService4) var bookmarkMeetingService4

    @Default(.bookmarkMeetingName5) var bookmarkMeetingName5
    @Default(.bookmarkMeetingURL5) var bookmarkMeetingURL5
    @Default(.bookmarkMeetingService5) var bookmarkMeetingService5

    var body: some View {
        VStack(alignment: .leading) {
            Section {
                HStack {
                    Text("Bookmark 1").font(.system(size: 12)).bold()
                    Button(action: reset(argument1: "bookmarkMeetingName", argument2: "bookmarkMeetingURL", argument3: "bookmarkMeetingService", argument4: KeyboardShortcuts.Name.joinBookmarkShortcut1)) {
                        Text("Reset").font(.system(size: 8))
                    }.disabled(bookmarkMeetingName.isEmpty && bookmarkMeetingURL.isEmpty)
                }
                HStack {
                    Picker(selection: $bookmarkMeetingService, label: Text("")) {
                        Text(MeetingServices.teams.rawValue).tag(MeetingServices.teams)
                        Text(MeetingServices.zoom.rawValue).tag(MeetingServices.zoom)
                        Text(MeetingServices.meet.rawValue).tag(MeetingServices.meet)
                        Text(MeetingServices.facetime.rawValue).tag(MeetingServices.facetime)
                        Text(MeetingServices.facetimeaudio.rawValue).tag(MeetingServices.facetimeaudio)
                        Text(MeetingServices.phone.rawValue).tag(MeetingServices.phone)
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL/Mail/Phone", text: $bookmarkMeetingURL).controlSize(ControlSize.small)
                }
                HStack {
                    TextField("Name (optional)", text: $bookmarkMeetingName).controlSize(ControlSize.small)
                    Text("Shortcut:").controlSize(ControlSize.small)
                    KeyboardShortcuts.Recorder(for: .joinBookmarkShortcut1).controlSize(ControlSize.small)
                }
            }
            Spacer()
            Section {
                HStack {
                    Text("Bookmark 2").font(.system(size: 12)).bold()
                    Button(action: reset(argument1: "bookmarkMeetingName2", argument2: "bookmarkMeetingURL2", argument3: "bookmarkMeetingService2", argument4: KeyboardShortcuts.Name.joinBookmarkShortcut2)) {
                        Text("Reset").font(.system(size: 8))
                    }.disabled(bookmarkMeetingName2.isEmpty && bookmarkMeetingURL2.isEmpty)
                }

                HStack {
                    Picker(selection: $bookmarkMeetingService2, label: Text("")) {
                        Text(MeetingServices.teams.rawValue).tag(MeetingServices.teams)
                        Text(MeetingServices.zoom.rawValue).tag(MeetingServices.zoom)
                        Text(MeetingServices.meet.rawValue).tag(MeetingServices.meet)
                        Text(MeetingServices.facetime.rawValue).tag(MeetingServices.facetime)
                        Text(MeetingServices.facetimeaudio.rawValue).tag(MeetingServices.facetimeaudio)
                        Text(MeetingServices.phone.rawValue).tag(MeetingServices.phone)
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL/Mail/Phone", text: $bookmarkMeetingURL2)
                }
                HStack {
                    TextField("Name (optional)", text: $bookmarkMeetingName2).controlSize(ControlSize.small)
                    Text("Shortcut:").controlSize(ControlSize.small)
                    KeyboardShortcuts.Recorder(for: .joinBookmarkShortcut2).controlSize(ControlSize.small)
                }
            }
            Spacer()
            Section {
                HStack {
                    Text("Bookmark 3").font(.system(size: 12)).bold()
                    Button(action: reset(argument1: "bookmarkMeetingName3", argument2: "bookmarkMeetingURL3", argument3: "bookmarkMeetingService3", argument4: KeyboardShortcuts.Name.joinBookmarkShortcut3)) {
                        Text("Reset").font(.system(size: 8))
                    }.disabled(bookmarkMeetingName.isEmpty && bookmarkMeetingURL.isEmpty)
                }
                HStack {
                    Picker(selection: $bookmarkMeetingService3, label: Text("")) {
                        Text(MeetingServices.teams.rawValue).tag(MeetingServices.teams)
                        Text(MeetingServices.zoom.rawValue).tag(MeetingServices.zoom)
                        Text(MeetingServices.meet.rawValue).tag(MeetingServices.meet)
                        Text(MeetingServices.facetime.rawValue).tag(MeetingServices.facetime)
                        Text(MeetingServices.facetimeaudio.rawValue).tag(MeetingServices.facetimeaudio)
                        Text(MeetingServices.phone.rawValue).tag(MeetingServices.phone)
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL/Mail/Phone", text: $bookmarkMeetingURL3).controlSize(ControlSize.small)
                }
                HStack {
                    TextField("Name (optional)", text: $bookmarkMeetingName3).controlSize(ControlSize.small)
                    Text("Shortcut:").controlSize(ControlSize.small)
                    KeyboardShortcuts.Recorder(for: .joinBookmarkShortcut3).controlSize(ControlSize.small)
                }
            }
            Spacer()
            Section {
                HStack {
                    Text("Bookmark 4").font(.system(size: 12)).bold()
                    Button(action: reset(argument1: "bookmarkMeetingName4", argument2: "bookmarkMeetingURL4", argument3: "bookmarkMeetingService4", argument4: KeyboardShortcuts.Name.joinBookmarkShortcut4)) {
                        Text("Reset").font(.system(size: 8))
                    }.disabled(bookmarkMeetingName.isEmpty && bookmarkMeetingURL.isEmpty)
                }
                HStack {
                    Picker(selection: $bookmarkMeetingService4, label: Text("")) {
                        Text(MeetingServices.teams.rawValue).tag(MeetingServices.teams)
                        Text(MeetingServices.zoom.rawValue).tag(MeetingServices.zoom)
                        Text(MeetingServices.meet.rawValue).tag(MeetingServices.meet)
                        Text(MeetingServices.facetime.rawValue).tag(MeetingServices.facetime)
                        Text(MeetingServices.facetimeaudio.rawValue).tag(MeetingServices.facetimeaudio)
                        Text(MeetingServices.phone.rawValue).tag(MeetingServices.phone)
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL/Mail/Phone", text: $bookmarkMeetingURL4)
                }
                HStack {
                    TextField("Name (optional)", text: $bookmarkMeetingName4).controlSize(ControlSize.small)
                    Text("Shortcut:").controlSize(ControlSize.small)
                    KeyboardShortcuts.Recorder(for: .joinBookmarkShortcut4).controlSize(ControlSize.small)
                }
            }
            Spacer()
            Section {
                HStack {
                    Text("Bookmark 5").font(.system(size: 12)).bold()
                    Button(action: reset(argument1: "bookmarkMeetingName5", argument2: "bookmarkMeetingURL5", argument3: "bookmarkMeetingService5", argument4: KeyboardShortcuts.Name.joinBookmarkShortcut5)) {
                        Text("Reset").font(.system(size: 8))
                    }.disabled(bookmarkMeetingName.isEmpty && bookmarkMeetingURL.isEmpty)
                }
                HStack {
                    Picker(selection: $bookmarkMeetingService5, label: Text("")) {
                        Text(MeetingServices.teams.rawValue).tag(MeetingServices.teams)
                        Text(MeetingServices.zoom.rawValue).tag(MeetingServices.zoom)
                        Text(MeetingServices.meet.rawValue).tag(MeetingServices.meet)
                        Text(MeetingServices.facetime.rawValue).tag(MeetingServices.facetime)
                        Text(MeetingServices.facetimeaudio.rawValue).tag(MeetingServices.facetimeaudio)
                        Text(MeetingServices.phone.rawValue).tag(MeetingServices.phone)
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL/Mail/Phone", text: $bookmarkMeetingURL5)
                }
                HStack {
                    TextField("Name (optional)", text: $bookmarkMeetingName5).controlSize(ControlSize.small)
                    Text("Shortcut:").controlSize(ControlSize.small)
                    KeyboardShortcuts.Recorder(for: .joinBookmarkShortcut5).controlSize(ControlSize.small)
                }
            }
            Spacer()
        }.padding()
    }


    func reset(argument1: String, argument2: String, argument3: String, argument4: KeyboardShortcuts.Name) -> () -> Void {
        {
            let bookmarkMeetingNameVariable = Defaults.Key<String?>(argument1)
            let bookmarkMeetingUrlVariable = Defaults.Key<String?>(argument2)
            let bookmarkMeetingServiceVariable = Defaults.Key<MeetingServices?>(argument3)

            Defaults[bookmarkMeetingNameVariable] = nil
            Defaults[bookmarkMeetingUrlVariable] = nil
            Defaults[bookmarkMeetingServiceVariable] = nil
            KeyboardShortcuts.reset(argument4)
        }
    }
}
