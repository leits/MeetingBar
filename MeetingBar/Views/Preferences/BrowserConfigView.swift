//
//  BrowserConfigView.swift
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

    @Default(.browsers) var browserConfigs

    @State var showingAddBrowserModal = false
    @State var showingEditBrowserModal = false
    @State private var showingAlert = false
    @State private var browser = Browser(name: "", path: "", arguments: "", deletable: true)

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(browserConfigs, id: \.self) { browser in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(browser.name)")
                            Text(generatePath(browser: browser)).font(.system(size: 11)).foregroundColor(Color.gray)
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
                }
            }
            .sheet(isPresented: $showingEditBrowserModal) {
                EditBrowserModal(browser: self.$browser)
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("preferences_configure_browsers_delete_alert_title".loco()),
                    message: Text("preferences_configure_browsers_delete_alert_message".loco(self.browser.name)),
                    primaryButton: .default(Text("general_delete".loco())) {
                        self.removeBrowser(self.browser)
                    },
                    secondaryButton: .cancel()
                )
            }

            HStack(alignment: .center, spacing: 20) {
                Spacer()
                MenuButton(label: Text("general_add".loco())) {
                    Button("preferences_configure_browsers_add_button_browser_title".loco()) {
                        self.showingAddBrowserModal.toggle()
                    }
                    Button("preferences_configure_browsers_add_button_all_system_title".loco()) {
                        self.addSystemBrowser()
                    }
                }
                .frame(width: 100, height: 20, alignment: .center)
                .sheet(isPresented: $showingAddBrowserModal) {
                    EditBrowserModal(browser: $browser)
                }

                Spacer()

                Button("general_close".loco()) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }.padding()
            .frame(width: 500,
                   height: 500,
                   alignment: .center)
    }

    private func generatePath(browser: Browser) -> String {
        var path = ""

        if !browser.path.isEmpty {
            path += " \(browser.path) "
        }

        if !browser.arguments.isEmpty {
            path += browser.arguments
        }

        return path
    }

    private func getPencilImage() -> NSImage {
        let pencilImage = NSImage(named: NSImage.touchBarComposeTemplateName)
        pencilImage!.size = NSSize(width: 16, height: 16)
        return pencilImage!
    }

    // allow to change the order of bookmarks
    private func addSystemBrowser() {
        addInstalledBrowser()
    }

    /**
     * allows to remove the bookmark
     */
    func removeBrowser(_ browser: Browser) {
        browserConfigs.removeAll { $0.name == browser.name }
    }

    struct EditBrowserModal: View {
        @Environment(\.presentationMode) var presentationMode
        @Default(.browsers) var browserConfigs

        @Binding var browser: Browser

        @State private var showingAlert = false
        @State private var error_msg = ""

        var body: some View {
            VStack {
                HStack {
                    if browser.name.isEmpty {
                        Text("preferences_configure_browsers_modal_add_browser_title".loco()).font(.headline)
                    } else {
                        Text("preferences_configure_browsers_modal_edit_browser_title".loco()).font(.headline)
                    }
                }
                Spacer()
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 15
                    ) {
                        Text("preferences_configure_browsers_modal_add_browser_name".loco())
                        Text("preferences_configure_browsers_modal_add_browser_path".loco())
                    }
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        TextField("", text: $browser.name)
                        TextField("", text: $browser.path)
                    }
                    VStack(
                        alignment: .leading
                    ) {
                        Button(action: chooseBrowser) {
                            Text("preferences_configure_browsers_modal_add_browser_choose_browser_button_title".loco())
                        }
                    }
                }
                Spacer()
                HStack {
                    Button(action: {
                        self.presentationMode.wrappedValue.dismiss()
                        self.browser = Browser(name: "", path: "", arguments: "", deletable: true)
                    }) {
                        Text("general_cancel".loco())
                    }

                    Button(action: saveBrowser) {
                        Text("general_save".loco())
                    }.disabled(self.browser.name.isEmpty || self.browser.name.isEmpty)
                }
            }.frame(width: 500, height: 200)
                .padding()
                .alert(isPresented: $showingAlert) {
                    Alert(title: Text("preferences_configure_browsers_modal_alert_title".loco()), message: Text(error_msg), dismissButton: .default(Text("general_ok".loco())))
                }
        }

        /**
         * saves the browser to the browsers configuration.
         */
        func saveBrowser() {
            presentationMode.wrappedValue.dismiss()

            let browserConfig = Browser(name: browser.name, path: browser.path, arguments: browser.arguments)
            browserConfigs.removeAll { $0.name == browser.name }
            browserConfigs.append(browserConfig)

            browserConfigs = browserConfigs.sorted { $0.path.fileName() < $1.path.fileName() }
            browser = Browser(name: "", path: "", arguments: "", deletable: true)
        }

        /**
         * opens a file chooser for the user to select a new browser to be added.
         */
        func chooseBrowser() {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = false
            openPanel.title = "preferences_configure_browsers_choose_broser_panel_title".loco()
            openPanel.prompt = "preferences_configure_browsers_choose_broser_panel_prompt".loco()
            openPanel.message = "preferences_configure_browsers_choose_broser_panel_message".loco()

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
