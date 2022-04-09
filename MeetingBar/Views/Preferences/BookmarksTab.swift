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
    @State private var showingAlert = false
    @State private var bookmark: Bookmark?

    var body: some View {
        VStack(alignment: .leading) {
            List {
                if self.bookmarks.isEmpty {
                    Text("preferences_bookmarks_no_bookmarks_placeholder".loco()).foregroundColor(Color.gray)
                }
                ForEach(bookmarks, id: \.self) { bookmark in
                    HStack {
                        Image(nsImage: NSImage(named: NSImage.listViewTemplateName)!).foregroundColor(.gray)

                        Text("\(bookmark.name) (\(bookmark.service.rawValue)): \(bookmark.url)")
                        Spacer()
                        Button(action: {
                            self.bookmark = bookmark
                            self.showingAlert = true
                        }) {
                            Image(nsImage: NSImage(named: NSImage.stopProgressFreestandingTemplateName)!)
                        }.buttonStyle(PlainButtonStyle())
                    }.padding(3)
                }.onMove(perform: moveBookmark)
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("preferences_bookmarks_delete_bookmark_title".loco()),
                    message: Text("preferences_bookmarks_delete_bookmark_message".loco(self.bookmark!.name)),
                    primaryButton: .default(Text("general_delete".loco())) {
                        self.removeBookmark(self.bookmark!)
                    },
                    secondaryButton: .cancel()
                )
            }

            HStack {
                Spacer()
                Button("preferences_bookmarks_add_bookmark_button".loco()) {
                    self.showingAddBookmarkModal.toggle()
                }.sheet(isPresented: $showingAddBookmarkModal) {
                    AddBookmarkModal()
                }
                Spacer()
            }
        }.padding()
    }

    // allow to change the order of bookmarks
    private func moveBookmark(source: IndexSet, destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
    }

    /**
     * allows to remove the bookmark
     */
    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.url == bookmark.url }
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
                        Text(MeetingServices.facetimeaudio.localizedValue).tag(MeetingServices.facetimeaudio)
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
                        error_msg = "preferences_bookmarks_new_bookmark_already_exist".loco(bookmark.name, url)
                        showingAlert = true
                    } else {
                        self.presentationMode.wrappedValue.dismiss()
                        guard let bookmarkURL = URL(string: url) else {
                            error_msg = "preferences_services_create_meeting_custom_url_placeholder".loco()
                            showingAlert = true
                            return
                        }
                        let bookmark = Bookmark(name: name, service: service, url: bookmarkURL)
                        bookmarks.append(bookmark)
                    }
                }) {
                    Text("general_add".loco())
                }.disabled(url.isEmpty || name.isEmpty)
            }
        }.frame(width: 500, height: 200)
            .padding()
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("preferences_bookmarks_new_bookmark_error_title".loco()), message: Text(error_msg), dismissButton: .default(Text("general_ok".loco())))
            }
    }
}
