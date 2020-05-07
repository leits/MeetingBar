//
//  AppDelegate.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import EventKit
import SwiftUI

struct LinksRegex {
    static let meet = try! NSRegularExpression(pattern: #"https://meet.google.com/.*"#)
    static let zoom = try! NSRegularExpression(pattern: #"https://zoom.us/j/.*"#)
}

enum AuthResult {
    case success(Bool), failure(Error)
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!

    var updateEventsActivity: NSBackgroundActivityScheduler?
    var reloadStatusBarTitleActivity: NSBackgroundActivityScheduler?


    private let eventStore = EKEventStore()
    private var calendar: EKCalendar?

    func applicationDidFinishLaunching(_: Notification) {
        eventStoreAccessCheck { result in
            switch result {
            case .success(let granted):
                if granted {
                    NSLog("Access to Calendar is granted")
                    self.setup()
                } else {
                    NSLog("Access to Calendar is denied")
                    NSApplication.shared.terminate(self)

                }
            case .failure(let error):
                print(error)
                NSApplication.shared.terminate(self)
            }
        }

    }

    func eventStoreAccessCheck(completion: @escaping (AuthResult) -> ()) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            completion(.success(true))
        case .denied, .notDetermined:
            eventStore.requestAccess(to: .event, completion:
                        { (granted: Bool, error: Error?) -> Void in
                        if error != nil {
                            completion(.failure(error!))
                        } else {
                            completion(.success(granted))
                        }
                })
        default:
            completion(.failure(NSError(domain:"Unknown authorization status", code: 0)))
        }
    }

    func setup() {
        DispatchQueue.main.async {
            let calendarTitle = (UserDefaults.standard.string(forKey: "calendarTitle") ?? "")
            self.calendar = getCalendar(title: calendarTitle, eventStore: self.eventStore)

            let statusBar = NSStatusBar.system
            self.statusBarItem = statusBar.statusItem(
                withLength: NSStatusItem.variableLength)

            let statusBarMenu = NSMenu(title: "Meeter in Status Bar Menu")
            self.statusBarItem.menu = statusBarMenu

            self.updateStatusBarMenu()
            self.updateStatusBarTitle()

            self.scheduleUpdateEvents()
            self.scheduleUpdateStatusBarTitle()
        }
    }


    private func scheduleUpdateStatusBarTitle() {
        let activity = NSBackgroundActivityScheduler(identifier: "leits.meeter.updatestatusbartitle")

        activity.repeats = true
        activity.interval = 60
        activity.qualityOfService = QualityOfService.userInitiated

        activity.schedule { (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            NSLog("Firing reccuring reloadStatusBarTitle")
            self.updateStatusBarTitle()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
        reloadStatusBarTitleActivity = activity
    }

    private func scheduleUpdateEvents() {
        // TODO: Subscribe to update evenets notification instead of force reload all events
        // https://developer.apple.com/documentation/eventkit/updating_with_notifications

        let activity = NSBackgroundActivityScheduler(identifier: "leits.meeter.updateevents")

        activity.repeats = true
        activity.interval = 60 * 5
        activity.qualityOfService = QualityOfService.utility

        activity.schedule { (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            NSLog("Firing reccuring updateEvents")
            self.updateStatusBarMenu()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
        updateEventsActivity = activity
    }

    func loadTodayEventsFromCalendar() -> [EKEvent] {
        if self.calendar == nil {
            NSLog("No loaded calendar")
            return []
        }
        let now = Date()
        let todayMidnight = Calendar.current.startOfDay(for: now)
        let tomorrowMidnight = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!

        let predicate = eventStore.predicateForEvents(withStart: todayMidnight, end: tomorrowMidnight, calendars: [self.calendar!])
        let calendarEvents = eventStore.events(matching: predicate)

        NSLog("Calendar \(self.calendar!.title) loaded")
        return calendarEvents
    }

    func updateStatusBarTitle() {
        var title = "🏁"

        let nextEvent = getNextEvent()

        if nextEvent != nil {
            let now = Date()
            let eventTitle = String((nextEvent?.title)!)
            var msg = ""
            if (nextEvent?.startDate)! < now, (nextEvent?.endDate)! > now {
                let eventEndTime = (nextEvent?.endDate.timeIntervalSinceNow)!
                let minutes = String(Int(eventEndTime) / 60)
                msg = " now (\(minutes) min left)"
            } else {
                let eventStartTime = (nextEvent?.startDate.timeIntervalSinceNow)!
                let minutes = Int(eventStartTime) / 60
                if minutes < 60 {
                    msg = " in \(minutes) min"
                } else if minutes < 120 {
                    msg = " in 1 hour"
                } else {
                    let hours = minutes / 60
                    msg = " in \(hours) hours"
                }
            }
            // TODO: Make title length customizable
            title = "\(eventTitle)\(msg)"
        }
        DispatchQueue.main.async {
            self.statusBarItem.button?.title = "\(title)"
        }
    }

    func updateStatusBarMenu() {
        let events: [EKEvent] = loadTodayEventsFromCalendar()

        let now = Date()

        let statusBarMenu = statusBarItem.menu!
        statusBarMenu.removeAllItems()

        // FIXME: Shortcut when menu isn't visible
        let joinItem = statusBarMenu.addItem(
            withTitle: "Join next meeting",
            action: #selector(AppDelegate.joinNextMeeting),
            keyEquivalent: "j")
        let nextEvent = getNextEvent()
        if nextEvent == nil {
            joinItem.isEnabled = false
        }
        statusBarMenu.addItem(NSMenuItem.separator())

        let todayFormatter = DateFormatter()
        todayFormatter.dateFormat = "E, d MMM"
        let todayDate = todayFormatter.string(from: now)
        let todayTitle = "Today meetings (\(todayDate)):"

        let titleItem = statusBarMenu.addItem(
            withTitle: todayTitle,
            action: nil,
            keyEquivalent: "")
        titleItem.isEnabled = false
        titleItem.attributedTitle = NSAttributedString(string: todayTitle, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 13)])

        let sortedEvents = events.sorted(by: { $0.startDate < $1.startDate })
        for event in sortedEvents {
            let eventTitle = String(event.title)

            let eventTimeFormatter = DateFormatter()
            eventTimeFormatter.dateFormat = "HH:mm"
            let eventStartTime = eventTimeFormatter.string(from: event.startDate)
            let eventEndTime = eventTimeFormatter.string(from: event.endDate)
            let eventDuration = event.endDate.timeIntervalSince(event.startDate)
            let eventDurationMinutes = String(Int(eventDuration) / 60)
            let eventOrganizer = (event.organizer?.name)!

            let itemTitle = "\(eventStartTime) - \(eventTitle)"
            let eventItem = statusBarMenu.addItem(
                withTitle: itemTitle,
                action: #selector(AppDelegate.clickItem),
                keyEquivalent: "")
            eventItem.representedObject = event


            if event.endDate < now {
                eventItem.state = NSControl.StateValue.on
            } else if event.startDate < now, event.endDate > now {
                eventItem.state = NSControl.StateValue.mixed
            } else {
                eventItem.state = NSControl.StateValue.off
            }

            let eventMenu = NSMenu(title: "Item \(eventTitle) menu")
            eventItem.submenu = eventMenu

            eventMenu.addItem(withTitle: eventTitle, action: nil, keyEquivalent: "")
            let durationTitle = "\(eventStartTime) - \(eventEndTime) (\(eventDurationMinutes) minutes)"
            eventMenu.addItem(withTitle: durationTitle, action: nil, keyEquivalent: "")
            eventMenu.addItem(NSMenuItem.separator())

            var status: String
            switch event.status {
            case.canceled:
                status = " 👎 Canceled"
            case.confirmed:
                status = " 👍 Confirmed"
            case.tentative:
                status = " ☝️ Tentative"
            default:
                status = " ❔ None"
            }
            eventMenu.addItem(withTitle: "Status: \(status)", action: nil, keyEquivalent: "")
            eventMenu.addItem(NSMenuItem.separator())


            if event.location != nil {
                eventMenu.addItem(withTitle: "Location:", action: nil, keyEquivalent: "")
                eventMenu.addItem(withTitle: "\(event.location!)", action: nil, keyEquivalent: "")
            }

            eventMenu.addItem(NSMenuItem.separator())

            eventMenu.addItem(withTitle: "Organizer:", action: nil, keyEquivalent: "")
            eventMenu.addItem(withTitle: "\(eventOrganizer)", action: nil, keyEquivalent: "")
            eventMenu.addItem(NSMenuItem.separator())

            if event.hasNotes {
                let notes = cleanUpNotes(notes: event.notes!)
                if notes.count > 0 {
                    eventMenu.addItem(withTitle: "Notes:", action: nil, keyEquivalent: "")
                    let item = eventMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
                    item.attributedTitle = NSAttributedString(string: notes)
                    eventMenu.addItem(NSMenuItem.separator())
                }
            }

            let attendeesCount = event.attendees!.count
            eventMenu.addItem(withTitle: "Attendees (\(attendeesCount)):", action: nil, keyEquivalent: "")
            let attendees: [EKParticipant] = event.attendees!
            for attendee in attendees {
                if attendee.isCurrentUser || !(attendee.participantType == EKParticipantType.person) {
                    continue
                }
                var attributes: [NSAttributedString.Key: Any] = [:]

                var roleMark: String
                switch attendee.participantRole {
                case .optional:
                    roleMark = "*"
                default:
                    roleMark = ""
                }

                var status: String
                switch attendee.participantStatus {
                case .declined:
                    status = ""
                    attributes[NSAttributedString.Key.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    attributes[NSAttributedString.Key.strikethroughColor] = NSColor.gray
                case .tentative:
                    status = " (t)"
                case .pending:
                    status = " (?)"
                default:
                    status = ""
                }

                let itemTitle = "- \(attendee.name!)\(roleMark) \(status)"
                let item = eventMenu.addItem(withTitle: itemTitle, action: nil, keyEquivalent: "")
                item.attributedTitle = NSAttributedString(string: itemTitle, attributes: attributes)
            }
        }
        statusBarMenu.addItem(NSMenuItem.separator())

        let calendarSelector = statusBarMenu.addItem(
            withTitle: "Calendar",
            action: nil,
            keyEquivalent: "")

        let calendarMenu = NSMenu(title: "Calendar selector")
        calendarSelector.submenu = calendarMenu

        let defaultCalendarTitle = UserDefaults.standard.string(forKey: "calendarTitle")
        let calendars = eventStore.calendars(for: .event)
        for calendar in calendars {
            let calendarItem = calendarMenu.addItem(
                withTitle: "\(calendar.title)",
                action: #selector(AppDelegate.selectCalendar),
                keyEquivalent: ""
            )
            if defaultCalendarTitle != nil && defaultCalendarTitle == calendar.title {
                calendarItem.state = NSControl.StateValue.on
            }
        }
        statusBarMenu.addItem(NSMenuItem.separator())


        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quit),
            keyEquivalent: ""
        )

    }
    @objc func quit(sender: NSStatusBarButton) {
        NSLog("User click Quit")
        NSApplication.shared.terminate(self)
    }

    @objc func selectCalendar(sender: NSStatusBarButton) {
        UserDefaults.standard.set(sender.title, forKey: "calendarTitle")
        calendar = getCalendar(title: sender.title, eventStore: eventStore)
        NSLog("Set \(sender.title) as default calendar")
        updateStatusBarMenu()
        updateStatusBarTitle()
    }

    @objc func joinNextMeeting(_: NSStatusBarButton) {
        NSLog("Click on join next event!")
        let nextEvent = getNextEvent()
        if nextEvent == nil {
            NSLog("No next event")
            return
        }
        openEvent(event: nextEvent!)
    }

    @objc func clickItem(sender: NSStatusBarButton) {
        NSLog("Click on event (\(sender.title))!")
        let item: NSMenuItem = (statusBarItem.menu?.item(withTitle: sender.title))!
        let event: EKEvent = item.representedObject as! EKEvent
        openEvent(event: event)
    }

    func getNextEvent() -> EKEvent? {
        if self.calendar == nil {
            NSLog("No loaded calendar")
            return nil
        }
        let now = Date()
        let nextMinute = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
        let todayMidnight = Calendar.current.startOfDay(for: now)
        let tomorrowMidnight = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!

        let predicate = eventStore.predicateForEvents(withStart: nextMinute, end: tomorrowMidnight, calendars: [self.calendar!])
        let nextEvent = eventStore.events(matching: predicate).first
        return nextEvent
    }

}

func openEvent(event: EKEvent) {
    // TODO: Make browser configurable
    let eventTitle = event.title!
    if event.notes == nil {
        NSLog("No notes for event (\(eventTitle))")
    }
    var eventLink = getMatch(text: (event.notes)!, regex: LinksRegex.meet)
    if eventLink != nil {
        openLinkInChrome(link: eventLink!)
    } else {
        NSLog("No meet link for event (\(eventTitle))")
        eventLink = getMatch(text: (event.notes)!, regex: LinksRegex.zoom)
        if eventLink != nil {
            openLinkInDefaultBrowser(link: eventLink!)
        }
        NSLog("No zoom link for event (\(eventTitle))")
    }
}

func getCalendar(title: String, eventStore: EKEventStore) -> EKCalendar? {
    let calendars = eventStore.calendars(for: .event)
    for calendar in calendars {
        if calendar.title == title {
            return calendar
        }
    }
    return nil
}

func getMatch(text: String, regex: NSRegularExpression) -> String? {
    let resultsIterator = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    let resultsMap = resultsIterator.map { String(text[Range($0.range, in: text)!]) }
    if !resultsMap.isEmpty {
        let meetLink = resultsMap[0]
        return meetLink
    }
    return nil
}

func openLinkInChrome(link: String) {
    let url = URL(string: link)!
    let configuration = NSWorkspace.OpenConfiguration()
    let chromeUrl = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    NSWorkspace.shared.open([url], withApplicationAt: chromeUrl, configuration: configuration, completionHandler: {
            _, _ in
            NSLog("Open \(url) in Chrome")
        })
}

func openLinkInDefaultBrowser(link: String) {
    let url = URL(string: link)!
    NSWorkspace.shared.open(url)
    NSLog("Open \(url) in default browser")
}

func cleanUpNotes(notes: String) -> String {
    let zoomSeparator = "\n──────────"
    let meetSeparator = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
    let cleanNotes = notes.components(separatedBy: zoomSeparator)[0].components(separatedBy: meetSeparator)[0]
    return cleanNotes
}
