//
//  AdvancedTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults

struct AdvancedTab: View {
    var body: some View {
        VStack(alignment: .leading) {
            ScriptSection()
            Divider()
            RegexesSection()
            Divider()
            HStack {
                Spacer()
                Text("preferences_advanced_setting_warning".loco())
                Spacer()
            }
        }.padding()
    }
}

struct ScriptSection: View {
    @Default(.runJoinEventScript) var runJoinEventScript
    @Default(.joinEventScript) var joinEventScript

    @State private var script = Defaults[.joinEventScript]
    @State private var showingAlert = false

    var body: some View {
        HStack {
            Toggle("preferences_advanced_apple_script_checkmark".loco(), isOn: $runJoinEventScript)
            Spacer()
            if script != joinEventScript {
                Button(action: saveScript) {
                    Text("preferences_advanced_save_script_button".loco())
                }
            }
        }.frame(height: 15)
        NSScrollableTextViewWrapper(text: $script).padding(.leading, 19)
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("preferences_advanced_wrong_location_title".loco()),
                      message: Text("preferences_advanced_wrong_location_message".loco()),
                      dismissButton: .default(Text("preferences_advanced_wrong_location_button".loco())))
            }
    }

    func saveScript() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowedFileTypes = ["none"]
        openPanel.allowsOtherFileTypes = false
        openPanel.prompt = "preferences_advanced_save_script_button".loco()
        openPanel.message = "preferences_advanced_wrong_location_message".loco()
        let scriptPath = try! FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        openPanel.directoryURL = scriptPath
        openPanel.begin { response in
            if response == .OK {
                if openPanel.url != scriptPath {
                    showingAlert = true
                    return
                }
                Defaults[.joinEventScriptLocation] = openPanel.url
                if let filepath = openPanel.url?.appendingPathComponent("joinEventScript.scpt") {
                    do {
                        try script.write(to: filepath, atomically: true, encoding: String.Encoding.utf8)
                        NSLog("Script saved")
                        joinEventScript = script
                    } catch {}
                }
            }
            openPanel.close()
        }
    }
}

struct NSScrollableTextViewWrapper: NSViewRepresentable {
    typealias NSViewType = NSScrollView
    var isEditable = true
    var textSize: CGFloat = 12

    @Binding var text: String

    var didEndEditing: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as? NSTextView
        textView?.font = NSFont.systemFont(ofSize: textSize)
        textView?.isEditable = isEditable
        textView?.isSelectable = true
        textView?.isAutomaticQuoteSubstitutionEnabled = false
        textView?.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context _: Context) {
        let textView = nsView.documentView as? NSTextView
        guard textView?.string != text else {
            return
        }

        textView?.string = text
        textView?.display() // force update UI to re-draw the string
        textView?.scrollRangeToVisible(NSRange(location: text.count, length: 0))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var view: NSScrollableTextViewWrapper

        init(_ view: NSScrollableTextViewWrapper) {
            self.view = view
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            view.text = textView.string
        }

        func textDidEndEditing(_: Notification) {
            view.didEndEditing?()
        }
    }
}

struct RegexesSection: View {
    @Default(.customRegexes) var customRegexes

    @State private var showingEditRegexModal = false
    @State private var selectedRegex = ""

    var body: some View {
        Section {
            HStack {
                Text("preferences_advanced_regex_title".loco())
                Spacer()
                Button("preferences_advanced_regex_add_button".loco()) { openEditRegexModal("") }
            }
            List {
                ForEach(customRegexes, id: \.self) { regex in
                    HStack {
                        Text(regex)
                        Spacer()
                        Button("preferences_advanced_regex_edit_button".loco()) { openEditRegexModal(regex) }
                        Button("preferences_advanced_regex_delete_button".loco()) { removeRegex(regex) }
                    }
                }
            }
            .sheet(isPresented: $showingEditRegexModal) {
                EditRegexModal(regex: selectedRegex, function: addRegex)
            }
        }.padding(.leading, 19)
    }

    func openEditRegexModal(_ regex: String) {
        selectedRegex = regex
        removeRegex(regex)
        showingEditRegexModal.toggle()
    }

    func addRegex(_ regex: String) {
        if !customRegexes.contains(regex) {
            customRegexes.append(regex)
        }
    }

    func removeRegex(_ regex: String) {
        if let index = customRegexes.firstIndex(of: regex) {
            customRegexes.remove(at: index)
        }
    }
}

struct EditRegexModal: View {
    @Environment(\.presentationMode) var presentationMode
    @State var new_regex: String = ""
    var regex: String
    var function: (_ regex: String) -> Void

    @State private var showingAlert = false
    @State private var error_msg = ""

    var body: some View {
        VStack {
            Spacer()
            TextField("preferences_advanced_regex_new_title".loco(), text: $new_regex)
            Spacer()
            HStack {
                Button(action: cancel) {
                    Text("general_cancel".loco())
                }
                Spacer()
                Button(action: save) {
                    Text("general_save".loco())
                }.disabled(new_regex.isEmpty)
            }
        }.padding()
            .frame(width: 500, height: 150)
            .onAppear { self.new_regex = self.regex }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("preferences_advanced_regex_new_cant_save_title".loco()), message: Text(error_msg), dismissButton: .default(Text("general_ok".loco())))
            }
    }

    func cancel() {
        if !regex.isEmpty {
            function(regex)
        }
        presentationMode.wrappedValue.dismiss()
    }

    func save() {
        do {
            _ = try NSRegularExpression(pattern: new_regex)
            function(new_regex)
            presentationMode.wrappedValue.dismiss()
        } catch let error as NSError {
            error_msg = error.localizedDescription
            showingAlert = true
        }
    }
}
