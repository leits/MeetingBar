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
                Text("⚠️ Use these settings only if you understand what they do")
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
            Toggle("Run AppleScript when joining to meeting", isOn: $runJoinEventScript)
            Spacer()
            if script != joinEventScript {
                Button(action: saveScript) {
                    Text("Save script")
                }
            }
        }.frame(height: 15)
        NSScrollableTextViewWrapper(text: $script).padding(.leading, 19)
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Wrong location"), message: Text("Please select the User > Library > Application Scripts > leits.MeetingBar folder"), dismissButton: .default(Text("Got it!")))
            }
    }

    func saveScript() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowedFileTypes = ["none"]
        openPanel.allowsOtherFileTypes = false
        openPanel.prompt = "Save script"
        openPanel.message = "Please select only User > Library > Application Scripts > leits.MeetingBar folder"
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
                Text("Custom regexes for meeting link")
                Spacer()
                Button("Add regex") { openEditRegexModal("") }
            }
            List {
                ForEach(customRegexes, id: \.self) { regex in
                    HStack {
                        Text(regex)
                        Spacer()
                        Button("edit") { openEditRegexModal(regex) }
                        Button("x") { removeRegex(regex) }
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
            TextField("Enter regex", text: $new_regex)
            Spacer()
            HStack {
                Button(action: cancel) {
                    Text("Cancel")
                }
                Spacer()
                Button(action: save) {
                    Text("Save")
                }.disabled(new_regex.isEmpty)
            }
        }.padding()
        .frame(width: 500, height: 150)
        .onAppear { self.new_regex = self.regex }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Can't save regex"), message: Text(error_msg), dismissButton: .default(Text("OK")))
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
