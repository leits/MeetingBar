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
                    title: Text("Delete bookmark?"),
                    message: Text("Do you want to delete bookmark \(self.bookmark!.name)?"),
                    primaryButton: .default(Text("Delete")) {
                        self.removeBookmark(self.bookmark!)
                    },
                    secondaryButton: .cancel()
                )
            }

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
                    if let bookmark = bookmarks.first(where: { $0.url == url }) {
                        error_msg = "A bookmark with this link/phone already exists with the name \(bookmark.name):\n\(url)"
                        showingAlert = true
                    } else {
                        self.presentationMode.wrappedValue.dismiss()
                        let bookmark = Bookmark(name: name, service: service, url: url)
                        bookmarks.append(bookmark)
                    }
                }) {
                    Text("Add")
                }.disabled(url.isEmpty || name.isEmpty)
            }
        }.frame(width: 500, height: 200)
        .padding()
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Can't add bookmark"), message: Text(error_msg), dismissButton: .default(Text("OK")))
        }
    }
}
