//
//  PreferencesView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit
import SwiftUI

import Defaults
import KeyboardShortcuts

struct PreferencesView: View {
    var body: some View {
        VStack {
            TabView {
                General().tabItem { Text("General") }
                StatusBar().tabItem { Text("Statusbar") }
                Menu().tabItem { Text("Menu") }
                Configuration().tabItem { Text("Services") }
                Calendars().tabItem { Text("Calendars") }
                Bookmark().tabItem { Text("Bookmarks") }
                Advanced().tabItem { Text("Advanced") }
            }
        }.padding()
    }
}

struct AboutApp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .center) {
                Spacer()
                Text("MeetingBar").font(.system(size: 20)).bold()
                if Bundle.main.infoDictionary != nil {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")").foregroundColor(.gray)
                }
                Spacer()
                HStack {
                    Button("About this app", action: openAboutThisApp)
                    Spacer()
                    Button("Support the creator", action: openSupportTheCreator)
                }
            }
        }
    }

    func openAboutThisApp() {
        NSLog("Open AboutThisApp")
        _ = openLinkInDefaultBrowser(Links.aboutThisApp)
    }

    func openSupportTheCreator() {
        NSLog("Open SupportTheCreator")
        _ = openLinkInDefaultBrowser(Links.supportTheCreator)
    }
}

struct Calendars: View {
    @State var calendarsBySource: [String: [EKCalendar]] = [:]
    @State var showingAddAcountModal = false

    @Default(.selectedCalendarIDs) var selectedCalendarIDs

    var body: some View {
        VStack {
            HStack {
                Text("Select calendars to show events in status bar")
                Spacer()
                Button(action: self.loadCalendarList) {
                    Image(nsImage: NSImage(named: NSImage.refreshTemplateName)!)
                }
            }
            VStack(alignment: .leading, spacing: 15) {
                Form {
                    Section {
                        List {
                            ForEach(Array(calendarsBySource.keys), id: \.self) { source in
                                Section(header: Text(source)) {
                                    ForEach(self.calendarsBySource[source]!, id: \.self) { calendar in
                                        CalendarRow(title: calendar.title, isSelected: self.selectedCalendarIDs.contains(calendar.calendarIdentifier), color: Color(calendar.color)) {
                                            if self.selectedCalendarIDs.contains(calendar.calendarIdentifier) {
                                                self.selectedCalendarIDs.removeAll { $0 == calendar.calendarIdentifier }
                                            } else {
                                                self.selectedCalendarIDs.append(calendar.calendarIdentifier)
                                            }
                                        }
                                    }
                                }
                            }
                        }.listStyle(SidebarListStyle())
                    }
                }
            }.border(Color.gray)
            HStack {
                Text("Don't see the calendar you need?")
                Button("Add account") { self.showingAddAcountModal.toggle() }
                    .sheet(isPresented: $showingAddAcountModal) {
                        AddAccountModal()
                    }
                Spacer()
            }
        }.onAppear { self.loadCalendarList() }
    }

    func loadCalendarList() {
        if let app = NSApplication.shared.delegate as! AppDelegate? {
            calendarsBySource = app.statusBarItem.eventStore.getAllCalendars()
        }
    }
}

struct AddAccountModal: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading) {
                Text(
                    """
                    To add external Calendars follow these steps:
                    1. Open the default Calendar App
                    2. Click 'Add Account' in the menu
                    3. Choose and connect your account
                    """
                )
            }
            Spacer()
            HStack {
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Close")
                }
            }
        }.padding().frame(width: 400, height: 200)
    }
}

struct CalendarRow: View {
    var title: String
    var isSelected: Bool
    var color: Color
    var action: () -> Void

    var body: some View {
        HStack {
            Button(action: self.action) {
                Section {
                    if self.isSelected {
                        Image(nsImage: NSImage(named: NSImage.menuOnStateTemplateName)!)
                    } else {
                        Image(nsImage: NSImage(named: NSImage.addTemplateName)!)
                    }
                }.frame(width: 20, height: 17)
            }
            Circle().fill(self.color).frame(width: 8, height: 8)
            Text(self.title)
        }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct General: View {
    @Default(.showEventsForPeriod) var showEventsForPeriod
    @Default(.launchAtLogin) var launchAtLogin
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Spacer()
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            Divider()
            Section {
                Picker("Show events for", selection: $showEventsForPeriod) {
                    Text("today").tag(ShowEventsForPeriod.today)
                    Text("today and tomorrow").tag(ShowEventsForPeriod.today_n_tomorrow)
                }.frame(width: 270, alignment: .leading)
                JoinEventNotificationPicker()
            }
            Section {
                HStack {
                    Text("Create meeting:")
                    KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
                    Spacer()
                    Text("Join next event meeting:")
                    KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                }
            }
            Spacer()
            Divider()
            AboutApp()
        }.padding()
    }
}

struct StatusBar: View {
    @Default(.eventTitleFormat) var eventTitleFormat
    @Default(.titleLength) var titleLength

    @Default(.timeFormat) var timeFormat
    @Default(.shortenEventTitle) var shortenEventTitle
    @Default(.menuEventTitleLength) var menuEventTitleLength
    @Default(.showEventEndDate) var showEventEndDate
    @Default(.showEventDetails) var showEventDetails
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.personalEventsAppereance) var personalEventsAppereance
    @Default(.pastEventsAppereance) var pastEventsAppereance
    @Default(.allDayEvents) var allDayEvents
    @Default(.allDayEventsWithLinkOnly) var allDayEventsWithLinkOnly

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Status bar").font(.headline).bold()
            Section {
                Section {
                    HStack {
                        Picker("Show", selection: $eventTitleFormat) {
                            Text("event title").tag(EventTitleFormat.show)
                            Text("dot (•)").tag(EventTitleFormat.dot)
                        }
                    }
                    HStack {
                        Text(generateTitleSample(eventTitleFormat, Int(titleLength)))
                        Spacer()
                    }.padding(.all, 10)
                    .border(Color.gray, width: 3)
                    HStack {
                        Text("5")
                        Slider(value: $titleLength, in: TitleLengthLimits.min ... TitleLengthLimits.max, step: 1)
                        Text("55")
                    }.disabled(eventTitleFormat != EventTitleFormat.show)
                    Text("Tip: If the app disappears from the status bar, make the length shorter").foregroundColor(Color.gray)
                }.padding(.horizontal, 10)
            }
            Spacer()
        }.padding()
    }
}

struct Menu: View {
    @Default(.timeFormat) var timeFormat
    @Default(.shortenEventTitle) var shortenEventTitle
    @Default(.menuEventTitleLength) var menuEventTitleLength
    @Default(.showEventEndDate) var showEventEndDate
    @Default(.showEventDetails) var showEventDetails
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon
    @Default(.declinedEventsAppereance) var declinedEventsAppereance
    @Default(.personalEventsAppereance) var personalEventsAppereance
    @Default(.pastEventsAppereance) var pastEventsAppereance
    @Default(.allDayEvents) var allDayEvents
    @Default(.allDayEventsWithLinkOnly) var allDayEventsWithLinkOnly

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Menu").font(.headline).bold()
            Section {
                HStack {
                    Toggle("Shorten event title", isOn: $shortenEventTitle)
                }

                HStack {
                    Text(generateTitleSample(Int(menuEventTitleLength))).lineLimit(nil)
                    Spacer()
                }.padding(.all, 10).border(Color.gray, width: 3)

                VStack {
                HStack {
                    Text("5")
                    Slider(value: $menuEventTitleLength, in: MenuTitleLengthLimits.min ... MenuTitleLengthLimits.max, step: 1)
                    Text("100")
                }.disabled(!shortenEventTitle)
                    Text(String(Int(menuEventTitleLength)))
                }
                Group {
                    Toggle("Show event end date", isOn: $showEventEndDate)
                    Toggle("Show event icon", isOn: $showMeetingServiceIcon)
                    Toggle("Show event details as submenu", isOn: $showEventDetails)
                    Toggle("Show event notes in details", isOn: $showEventDetails).padding(.leading, 30)


                    HStack {
                        Toggle("Show all day events", isOn: $allDayEvents)
                        Toggle("... with meeting links only", isOn: ($allDayEventsWithLinkOnly)).disabled(!$allDayEvents.wrappedValue)
                    }

                    HStack {
                        Picker("Past events:", selection: $pastEventsAppereance) {
                            Text("show").tag(PastEventsAppereance.show_active)
                            Text("show as inactive").tag(PastEventsAppereance.show_inactive)
                            Text("hide").tag(PastEventsAppereance.hide)
                        }
                    }
                    HStack {
                        Picker("Declined events:", selection: $declinedEventsAppereance) {
                            Text("show with strikethrough").tag(DeclinedEventsAppereance.strikethrough)
                            Text("hide").tag(DeclinedEventsAppereance.hide)
                        }
                    }
                    HStack {
                        Picker("Events without guests:", selection: $personalEventsAppereance) {
                            Text("show").tag(PastEventsAppereance.show_active)
                            Text("show as inactive").tag(PastEventsAppereance.show_inactive)
                            Text("hide").tag(PastEventsAppereance.hide)
                        }
                    }
                    HStack {
                        Picker("Time format:", selection: $timeFormat) {
                            Text("12-hour (AM/PM)").tag(TimeFormat.am_pm)
                            Text("24-hour").tag(TimeFormat.military)
                        }
                    }
                }
            }.padding(.horizontal, 10)

            Spacer()
        }.padding()
    }
}

struct Configuration: View {
    @Default(.useChromeForMeetLinks) var useChromeForMeetLinks
    @Default(.useChromeForHangoutsLinks) var useChromeForHangoutsLinks
    @Default(.useAppForZoomLinks) var useAppForZoomLinks
    @Default(.useAppForTeamsLinks) var useAppForTeamsLinks

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Section {
                Picker(selection: $useChromeForMeetLinks, label: Text("Open Meet links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(ChromeExecutable.defaultBrowser)
                    Text("Chrome").tag(ChromeExecutable.chrome)
                    Text("Chromium").tag(ChromeExecutable.chromium)
                }
                Picker(selection: $useAppForZoomLinks, label: Text("Open Zoom links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Zoom app").tag(true)
                }
                Picker(selection: $useAppForTeamsLinks, label: Text("Open Teams links in").frame(width: 150, alignment: .leading)) {
                    Text("Default Browser").tag(false)
                    Text("Teams app").tag(true)
                }
            }.padding(.horizontal, 10)
            Section {
                Text("Supported links for services:\n\(MeetingServices.allCases.map { $0.rawValue }.joined(separator: ", "))")
                HStack {
                    Text("If the service you use isn't supported, email me")
                    Button("✉️", action: emailMe)
                }
            }.foregroundColor(.gray).font(.system(size: 12)).padding(.horizontal, 10)
            Divider()
            HStack {
                Text("Create meetings in").frame(width: 150, alignment: .leading)
                CreateMeetingServicePicker()
            }.padding(.horizontal, 10)
        }.padding()
    }
}

struct Bookmark: View {
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
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL", text: $bookmarkMeetingURL).controlSize(ControlSize.small)
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
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL", text: $bookmarkMeetingURL2)
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
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL", text: $bookmarkMeetingURL3).controlSize(ControlSize.small)
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
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL", text: $bookmarkMeetingURL4)
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
                        Text(MeetingServices.other.rawValue).tag(MeetingServices.other)
                    }.labelsHidden()
                    .controlSize(ControlSize.small)
                    .frame(width: 150, alignment: .leading)
                    TextField("URL", text: $bookmarkMeetingURL5)
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



struct CreateMeetingServicePicker: View {
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        Picker(selection: $createMeetingService, label: Text("")) {
            Text(CreateMeetingServices.meet.rawValue).tag(CreateMeetingServices.meet)
            Text(CreateMeetingServices.zoom.rawValue).tag(CreateMeetingServices.zoom)
            Text(CreateMeetingServices.teams.rawValue).tag(CreateMeetingServices.teams)
            Text(CreateMeetingServices.hangouts.rawValue).tag(CreateMeetingServices.hangouts)
            Text(CreateMeetingServices.gcalendar.rawValue).tag(CreateMeetingServices.gcalendar)
            Text(CreateMeetingServices.outlook_live.rawValue).tag(CreateMeetingServices.outlook_live)
            Text(CreateMeetingServices.outlook_office365.rawValue).tag(CreateMeetingServices.outlook_office365)
        }.labelsHidden()
    }
}

struct JoinEventNotificationPicker: View {
    @Default(.joinEventNotification) var joinEventNotification
    @Default(.joinEventNotificationTime) var joinEventNotificationTime

    var body: some View {
        HStack {
            Toggle("Send notification to join next event meeting", isOn: $joinEventNotification)
            Picker("", selection: $joinEventNotificationTime) {
                Text("when event starts").tag(JoinEventNotificationTime.atStart)
                Text("1 minute before").tag(JoinEventNotificationTime.minuteBefore)
                Text("3 minutes before").tag(JoinEventNotificationTime.threeMinuteBefore)
                Text("5 minutes before").tag(JoinEventNotificationTime.fiveMinuteBefore)
            }.frame(width: 150, alignment: .leading).labelsHidden().disabled(!joinEventNotification)
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

struct Advanced: View {
    var body: some View {
        VStack(alignment: .leading) {
            ScriptView()
            Divider()
            RegexesView()
            Divider()
            HStack {
                Spacer()
                Text("⚠️ Use these settings only if you understand what they do")
                Spacer()
            }
        }.padding()
    }
}

struct ScriptView: View {
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

struct RegexesView: View {
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
