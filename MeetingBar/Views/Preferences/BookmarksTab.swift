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
    @Default(.bookmarks) var bookmarks

    @State var showingAddBookmarkModal = false

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(bookmarks, id: \.self) { bookmark in
                    HStack {
                        Text("\(bookmark.name) (\(bookmark.service.rawValue)): \(bookmark.url)")
                        Spacer()
                        Button("x") {
                            self.removeBookmark(bookmark)
                        }
                    }
                }
            }.border(Color.gray)
            HStack {
                Spacer()
                Button("Add bookmark") {
                    self.showingAddBookmarkModal.toggle()
                }.sheet(isPresented: $showingAddBookmarkModal) {
                    AddBookmarkModal()
                }
                Spacer()
            }
        }.padding()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.url == bookmark.url }
    }
}

struct AddBookmarkModal: View {
    @Environment(\.presentationMode) var presentationMode

    @Default(.bookmarks) var bookmarks

    @State var name: String = ""
    @State var url: String = ""
    @State var service = MeetingServices.meet




    var body: some View {
        VStack {
            HStack {
                Text("New bookmark").font(.headline)
            }
            Spacer()
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 15
                ) {
                    Text("Name")
                    Text("Link/Phone")
                    Text("Service")
                }
                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    TextField("", text: $name)
                    TextField("", text: $url)
                    Picker(selection: $service, label: Text("")) {
                        Text(MeetingServices.teams.rawValue).tag(MeetingServices.teams)
                        Text(MeetingServices.zoom.rawValue).tag(MeetingServices.zoom)
                        Text(MeetingServices.meet.rawValue).tag(MeetingServices.meet)
                        Text(MeetingServices.facetime.rawValue).tag(MeetingServices.facetime)
                        Text(MeetingServices.facetimeaudio.rawValue).tag(MeetingServices.facetimeaudio)
                        Text(MeetingServices.phone.rawValue).tag(MeetingServices.phone)
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                }
            }
            Spacer()
            HStack {
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                }
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                    let bookmark = Bookmark(name: name, service: service, url: url)
                    bookmarks.append(bookmark)
                }) {
                    Text("Add")
                }.disabled(url.isEmpty || name.isEmpty)
            }
        }.padding().frame(width: 500, height: 200)
    }
}
