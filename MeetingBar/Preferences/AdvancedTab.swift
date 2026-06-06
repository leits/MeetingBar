//
//  AdvancedTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

struct AdvancedTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "preferences_advanced_setting_warning".loco(),
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            GroupBox(
                label: Label(
                    "preferences_section_apple_script_hooks_title".loco(),
                    systemImage: "applescript")
            ) {
                VStack(spacing: 10) {
                    ScriptSection()
                }
            }
            GroupBox(
                label: Label(
                    "preferences_section_regex_filters_title".loco(),
                    systemImage: "line.horizontal.3.decrease.circle")
            ) {
                VStack(spacing: 10) {
                    FilterEventRegexesSection()
                    MeetingRegexesSection()
                }
            }
            Spacer()
        }
    }
}

struct ScriptSection: View {
    @EnvironmentObject var calendarSync: CalendarSync
    @Default(.runEventStartScript) var runEventStartScript
    @Default(.eventStartScriptLocation) var eventStartScriptLocation
    @Default(.eventStartScript) var eventStartScript
    @Default(.eventStartScriptTime) var eventStartScriptTime

    @State private var showingRunEventStartScriptModal = false

    @Default(.runJoinEventScript) var runJoinEventScript
    @Default(.joinEventScriptLocation) var joinEventScriptLocation
    @Default(.joinEventScript) var joinEventScript

    @State private var showingJoinEventScriptModal = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Toggle(
                    "preferences_advanced_run_script_on_event_start".loco(),
                    isOn: $runEventStartScript)
                Picker("", selection: $eventStartScriptTime) {
                    Text("general_when_event_starts".loco()).tag(TimeBeforeEvent.atStart)
                    Text("general_one_minute_before".loco()).tag(TimeBeforeEvent.minuteBefore)
                    Text("general_three_minute_before".loco()).tag(
                        TimeBeforeEvent.threeMinuteBefore)
                    Text("general_five_minute_before".loco()).tag(TimeBeforeEvent.fiveMinuteBefore)
                }.frame(width: 150, alignment: .leading).labelsHidden().disabled(
                    !runEventStartScript)
                Spacer()
                if runEventStartScript {
                    Button(action: runSampleScript) {
                        Text("preferences_advanced_test_script_on_next_event".loco())
                    }
                    Button("preferences_advanced_edit_script".loco()) {
                        showingRunEventStartScriptModal = true
                    }
                }
            }.sheet(isPresented: $showingRunEventStartScriptModal) {
                EditScriptModal(
                    script: $eventStartScript, scriptLocation: $eventStartScriptLocation,
                    scriptName: "eventStartScript.scpt")
            }

            HStack {
                Toggle(
                    "preferences_advanced_apple_script_checkmark".loco(), isOn: $runJoinEventScript)
                Spacer()
                if runJoinEventScript {
                    Button("preferences_advanced_edit_script".loco()) {
                        showingJoinEventScriptModal = true
                    }
                }
            }.sheet(isPresented: $showingJoinEventScriptModal) {
                EditScriptModal(
                    script: $joinEventScript, scriptLocation: $joinEventScriptLocation,
                    scriptName: "joinEventScript.scpt")
            }
        }
    }

    func runSampleScript() {
        runAppleScriptForNextEvent(events: calendarSync.events)
    }
}

struct EditScriptModal: View {
    @Environment(\.presentationMode) var presentationMode

    @Binding var script: String
    @Binding var scriptLocation: URL?
    var scriptName: String

    @State var editedScript: String = ""

    @State private var showingAlert = false

    var body: some View {
        VStack {
            Spacer()
            Text("preferences_advanced_edit_script".loco())
            Spacer()
            NSScrollableTextViewWrapper(text: $editedScript).padding(.leading, 19)
            Spacer()
            HStack {
                Button(action: cancel) {
                    Text("general_cancel".loco())
                }
                Spacer()
                Button(action: saveScript) {
                    Text("general_save".loco())
                }.disabled(self.editedScript == self.script)
            }
            Spacer()
        }.padding()
            .frame(width: 500, height: 500)
            .onAppear { self.editedScript = self.script }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("preferences_advanced_wrong_location_title".loco()),
                    message: Text("preferences_advanced_wrong_location_message".loco()),
                    dismissButton: .default(
                        Text("preferences_advanced_wrong_location_button".loco())))
            }
    }

    func saveScript() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowedContentTypes = [.appleScript]
        openPanel.allowsOtherFileTypes = false
        openPanel.prompt = "preferences_advanced_save_script_button".loco()
        openPanel.message = "preferences_advanced_wrong_location_message".loco()
        let scriptPath = try! FileManager.default.url(
            for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        openPanel.directoryURL = scriptPath
        openPanel.begin { response in
            if response == .OK {
                if openPanel.url != scriptPath {
                    showingAlert = true
                    return
                }
                scriptLocation = openPanel.url
                if let filepath = openPanel.url?.appendingPathComponent(scriptName) {
                    do {
                        try editedScript.write(
                            to: filepath, atomically: true, encoding: String.Encoding.utf8)
                        script = editedScript
                        presentationMode.wrappedValue.dismiss()
                    } catch {}
                }
            }
            openPanel.close()
        }
    }

    func cancel() {
        presentationMode.wrappedValue.dismiss()
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
        textView?.display()  // force update UI to re-draw the string
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

struct FilterEventRegexesSection: View {
    @Default(.filterEventRegexes) var filterEventRegexes

    @State private var showingEditRegexModal = false
    @State private var regexDraft = RegexEditDraft.adding()

    var body: some View {
        DisclosureGroup("preferences_advanced_event_regex_title".loco()) {
            List {
                Button("preferences_advanced_regex_add_button".loco(), action: openAddRegexModal)
                    .buttonStyle(.borderedProminent)
                ForEach(filterEventRegexes, id: \.self) { regex in
                    HStack {
                        Text(regex)
                        Spacer()
                        Button("preferences_advanced_regex_edit_button".loco()) {
                            openEditRegexModal(for: regex)
                        }
                        Button("x") { removeRegex(regex) }
                    }
                }
            }.frame(height: 100)
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .sheet(isPresented: $showingEditRegexModal) {
                    EditRegexModal(regex: regexDraft.value, onSave: saveRegex)
                }
        }.padding(.leading, 19)
    }

    func openAddRegexModal() {
        regexDraft = .adding()
        showingEditRegexModal = true
    }

    func openEditRegexModal(for regex: String) {
        regexDraft = .editing(regex)
        showingEditRegexModal = true
    }

    func saveRegex(_ regex: String) -> Bool {
        regexDraft.value = regex
        switch RegexListEditingPolicy.saving(regexDraft, in: filterEventRegexes) {
        case .saved(let updated):
            filterEventRegexes = updated
            return true
        case .duplicate, .originalMissing:
            return false
        }
    }

    func removeRegex(_ regex: String) {
        if let index = filterEventRegexes.firstIndex(of: regex) {
            filterEventRegexes.remove(at: index)
        }
    }
}

struct MeetingRegexesSection: View {
    @Default(.customRegexes) var customRegexes

    @State private var showingEditRegexModal = false
    @State private var regexDraft = RegexEditDraft.adding()
    @State private var regexTestText = ""
    @State private var regexTestResult: String?
    @State private var regexTestMatched = false

    var body: some View {
        DisclosureGroup("preferences_advanced_regex_title".loco()) {
            VStack(alignment: .leading, spacing: 8) {
                List {
                    Button("preferences_advanced_regex_add_button".loco()) {
                        openAddRegexModal()
                    }.buttonStyle(.borderedProminent)
                    ForEach(customRegexes, id: \.self) { regex in
                        HStack {
                            Text(regex)
                            Spacer()
                            Button("preferences_advanced_regex_edit_button".loco()) {
                                openEditRegexModal(for: regex)
                            }
                            Button("x") { removeRegex(regex) }
                        }
                    }
                }
                .frame(height: 100)
                .listStyle(.inset(alternatesRowBackgrounds: true))

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("preferences_advanced_regex_test_title".loco())
                        .font(.subheadline)
                    TextField(
                        "preferences_advanced_regex_test_placeholder".loco(), text: $regexTestText
                    )
                    .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("preferences_advanced_regex_test_button".loco(), action: testRegex)
                            .disabled(regexTestText.isEmpty || customRegexes.isEmpty)
                        if let regexTestResult {
                            Text(regexTestResult)
                                .foregroundColor(regexTestMatched ? .secondary : .red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEditRegexModal) {
                EditRegexModal(regex: regexDraft.value, onSave: saveRegex)
            }
        }.padding(.leading, 19)
    }

    func openAddRegexModal() {
        regexDraft = .adding()
        showingEditRegexModal = true
    }

    func openEditRegexModal(for regex: String) {
        regexDraft = .editing(regex)
        showingEditRegexModal = true
    }

    func saveRegex(_ regex: String) -> Bool {
        regexDraft.value = regex
        switch RegexListEditingPolicy.saving(regexDraft, in: customRegexes) {
        case .saved(let updated):
            customRegexes = updated
            return true
        case .duplicate, .originalMissing:
            return false
        }
    }

    func removeRegex(_ regex: String) {
        if let index = customRegexes.firstIndex(of: regex) {
            customRegexes.remove(at: index)
        }
    }

    func testRegex() {
        let customCandidates = MeetingLinkDetector.allCandidates(
            location: nil,
            eventURL: nil,
            notes: regexTestText,
            calendarEmail: nil,
            currentUserEmail: nil,
            customRegexes: customRegexes
        ).filter { $0.source == .customRegex }

        if let candidate = customCandidates.first {
            regexTestMatched = true
            regexTestResult = "preferences_advanced_regex_test_match".loco(
                candidate.url.absoluteString)
        } else {
            regexTestMatched = false
            regexTestResult = "preferences_advanced_regex_test_no_match".loco()
        }
    }
}

struct EditRegexModal: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var draftRegex: String
    let onSave: (_ regex: String) -> Bool

    @State private var showingAlert = false
    @State private var errorMessage = ""

    init(regex: String, onSave: @escaping (_ regex: String) -> Bool) {
        _draftRegex = State(initialValue: regex)
        self.onSave = onSave
    }

    var body: some View {
        VStack {
            Spacer()
            TextField("preferences_advanced_regex_new_title".loco(), text: $draftRegex)
            Spacer()
            HStack {
                Button(action: cancel) {
                    Text("general_cancel".loco())
                }
                Spacer()
                Button(action: save) {
                    Text("general_save".loco())
                }.disabled(draftRegex.isEmpty)
            }
        }.padding()
            .frame(width: 500, height: 150)
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("preferences_advanced_regex_new_cant_save_title".loco()),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("general_ok".loco()))
                )
            }
    }

    func cancel() {
        presentationMode.wrappedValue.dismiss()
    }

    func save() {
        do {
            _ = try NSRegularExpression(pattern: draftRegex)
            if onSave(draftRegex) {
                presentationMode.wrappedValue.dismiss()
            } else {
                errorMessage = "preferences_advanced_regex_duplicate_error".loco()
                showingAlert = true
            }
        } catch let error as NSError {
            errorMessage = error.localizedDescription
            showingAlert = true
        }
    }
}

#Preview {
    AdvancedTab().padding().frame(width: 700, height: 620)
}
