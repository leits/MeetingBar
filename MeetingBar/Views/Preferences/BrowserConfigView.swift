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

struct BrowserConfigView: View {
    @Environment(\.presentationMode) var presentationMode

    @Default(.browser) var browserConfigs

    @State var showingAddBrowserModal = false
    @State var showingEditBrowserModal = false
    @State private var showingAlert = false
    @State private var showingDeleteAllAlert = false
    @State private var browser = Browser(name: "", path: "", arguments: "", deletable: true)

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(browserConfigs, id: \.self) { browser in
                    HStack {
                        Image(nsImage: NSImage(named: NSImage.listViewTemplateName)!).foregroundColor(.gray)

                        VStack(alignment: .leading) {
                            Text("\(browser.name)")
                            Text(generatePath(browser: browser)).font(.system(size:11)).foregroundColor(Color.gray)
                        }

                        Spacer()

                        Button(action: {
                            self.browser = browser
                            self.showingEditBrowserModal.toggle()
                        }) {
                            Image(nsImage: getPencilImage())
                        }.buttonStyle(PlainButtonStyle())

                        Button(action: {
                            self.browser = browser
                            self.showingAlert = true
                        }) {
                            Image(nsImage: NSImage(named: NSImage.stopProgressFreestandingTemplateName)!)
                        }.buttonStyle(PlainButtonStyle())
                    }.padding(3)
                }.onMove(perform: moveBrowser)
            }
            .sheet(isPresented: $showingEditBrowserModal) {
                EditBrowserModal(browser: self.$browser)
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("Delete browser?"),
                    message: Text("Do you want to delete the browser configuration \(self.browser.name)?"),
                    primaryButton: .default(Text("Delete")) {
                        self.removeBrowser(self.browser)
                    },
                    secondaryButton: .cancel()
                )
            }

            HStack(alignment: .center, spacing: 20) {
                Spacer()
                MenuButton(label: Image(nsImage: NSImage(named: NSImage.addTemplateName)!)) {
                    Button("Custom browser") {
                        self.showingAddBrowserModal.toggle()
                    }
                    Button("All system browser") {
                        self.addSystemBrowser()
                    }
                }
                .frame(width: 20, height: 20, alignment: .center)
                .menuButtonStyle(BorderlessPullDownMenuButtonStyle())
                .sheet(isPresented: $showingAddBrowserModal) {
                    EditBrowserModal(browser: $browser)
                }

                Button(action: {
                    self.showingDeleteAllAlert = true
                }) {
                    Image(nsImage: NSImage(named: NSImage.touchBarDeleteTemplateName)!)
                    if #available(OSX 11.0, *) {
                        //   image.offset(x: 0.0, y: 4.0)
                    }
                }.buttonStyle(BorderlessButtonStyle())

                Spacer()

                Button("OK") {
                    presentationMode.wrappedValue.dismiss()
                }.frame(width: 20, height: 20, alignment: .trailing)
            }
            .alert(isPresented: $showingDeleteAllAlert) {
                Alert(
                    title: Text("Delete all browser configs?"),
                    message: Text("Do you want to delete all browser configs?"),
                    primaryButton: .default(Text("Delete all")) {
                        self.removeAllBrowser()
                    },
                    secondaryButton: .cancel()
                )
            }
        }.padding()
        .frame(width: 500,
               height: 500,
               alignment: .center)
    }

    private func generatePath (browser: Browser) -> String {
        var path: String = ""

        if !browser.path.isEmpty {
            path += " \(browser.path) "
        }

        if !browser.arguments.isEmpty {
            path += browser.arguments
        }

        return path
    }

    private func getPencilImage() -> NSImage {
        let pencilImage = NSImage(named: "pencil")
        pencilImage!.size = NSSize(width: 16, height: 16)
        return pencilImage!
    }

    // allow to change the order of bookmarks
    private func moveBrowser(source: IndexSet, destination: Int) {
        browserConfigs.move(fromOffsets: source, toOffset: destination)
    }

    // allow to change the order of bookmarks
    private func addSystemBrowser() {
        addInstalledBrowser()
    }

    // allow to change the order of bookmarks
    private func removeAllBrowser() {
        Defaults[.browser] = []
    }

    /**
     * allows to remove the bookmark
     */
    func removeBrowser(_ browser: Browser) {
        browserConfigs.removeAll { $0.name == browser.name }
    }


    struct EditBrowserModal: View {
        @Environment(\.presentationMode) var presentationMode
        @Default(.browser) var browserConfigs

        @Binding var browser: Browser

        @State private var showingAlert = false
        @State private var error_msg = ""

        var body: some View {
            VStack {
                HStack {
                    if browser.name.isEmpty {
                        Text("Add browser").font(.headline)
                    } else {
                        Text("Edit browser").font(.headline)
                    }
                }
                Spacer()
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 15
                    ) {
                        Text("Name")
                        Text("Path")
                        //      Text("Arguments")
                    }
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        TextField("", text: $browser.name)
                        TextField("", text: $browser.path)
                        //    TextField("", text: $browser.arguments)
                    }
                    VStack(
                        alignment: .leading
                        //spacing: 10
                    ) {
                        Button(action: chooseApplication) {
                            Text("Choose browser")
                        }
                    }
                }
                Spacer()
                HStack {
                    Button(action: {
                        self.presentationMode.wrappedValue.dismiss()
                        self.browser = Browser(name: "", path: "", arguments: "", deletable: true)
                    }) {
                        Text("Cancel")
                    }

                    Button(action: {
                        self.presentationMode.wrappedValue.dismiss()

                        let browserConfig = Browser(name: browser.name, path: browser.path, arguments: browser.arguments)
                        browserConfigs.removeAll { $0.name == browser.name }
                        browserConfigs.append(browserConfig)

                        browserConfigs = browserConfigs.sorted { $0.path.fileName() < $1.path.fileName() }
                        self.browser = Browser(name: "", path: "", arguments: "", deletable: true)
                    }) {
                        Text("Save")
                    }.disabled(self.browser.name.isEmpty || self.browser.name.isEmpty)
                }
            }.frame(width: 500, height: 200)
            .padding()
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Can't add browser config"), message: Text(error_msg), dismissButton: .default(Text("OK")))
            }
        }

        func chooseApplication() {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = false
            openPanel.title = "Select a valid browser app"
            openPanel.prompt = "Choose browser"
            openPanel.message = "Please select a browser from any path!"

            let appPath = try! FileManager.default.url(for: .allApplicationsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

            openPanel.directoryURL = appPath
            openPanel.begin { response in
                if response == .OK {
                    self.browser.path = (openPanel.url?.path)!
                    self.browser.name = openPanel.url!.deletingPathExtension().lastPathComponent.fileName()
                    openPanel.close()
                }
            }
        }
    }
}
