//
//  StatusBarItemControler.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import EventKit

import Defaults
import KeyboardShortcuts

class StatusBarItemControler {
    let item: NSStatusItem
    let eventStore = EKEventStore()
    var calendars: [EKCalendar] = []

    init() {
        self.item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        let statusBarMenu = NSMenu(title: "MeetingBar in Status Bar Menu")
        self.item.menu = statusBarMenu
        self.calendars = self.eventStore.getCalendars(Defaults[.selectedCalendars])
    }

    func updateTitle() {
        var title = "Choose your calendars"

        if !self.calendars.isEmpty {
            let nextEvent = self.eventStore.getNextEvent(calendars: self.calendars)
            if let nextEvent = nextEvent {
                title = createEventStatusString(nextEvent)
            } else {
                title = "🏁"
            }
        } else {
            NSLog("No loaded calendars")
        }
        DispatchQueue.main.async {
            if let button = self.item.button {
                button.title = "\(title)"
            }
        }
    }

    func updateMenu() {
        if let statusBarMenu = self.item.menu {
            statusBarMenu.autoenablesItems = false
            statusBarMenu.removeAllItems()

            if !self.calendars.isEmpty {
                self.createTodaySection()
                statusBarMenu.addItem(NSMenuItem.separator())
            }
            self.createJoinSection()
            statusBarMenu.addItem(NSMenuItem.separator())

            self.createPreferencesSection()
        }
    }

    func createJoinSection() {
        if !self.calendars.isEmpty {
            let nextEvent = self.eventStore.getNextEvent(calendars: self.calendars)
            if nextEvent != nil {
                let joinItem = self.item.menu!.addItem(
                    withTitle: "Join next event",
                    action: #selector(AppDelegate.joinNextMeeting),
                    keyEquivalent: "")
                joinItem.setShortcut(for: .joinEventShortcut)
            }
        }
        let createItem = self.item.menu!.addItem(
            withTitle: "Create meeting",
            action: #selector(AppDelegate.createMeeting),
            keyEquivalent: "")
        createItem.setShortcut(for: .createMeetingShortcut)
    }

    func createTodaySection() {
        let events: [EKEvent] = self.eventStore.loadTodayEvents(calendars: self.calendars)
        let now = Date()

        // Today header
        let todayFormatter = DateFormatter()
        todayFormatter.dateFormat = "E, d MMM"
        let todayDate = todayFormatter.string(from: now)
        let todayTitle = "Today events (\(todayDate)):"
        let titleItem = self.item.menu!.addItem(
            withTitle: todayTitle,
            action: nil,
            keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(string: todayTitle, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 13)])
        titleItem.isEnabled = false

        let sortedEvents = events.sorted(by: { $0.startDate < $1.startDate })

        if sortedEvents.count == 0 {
            let item = self.item.menu!.addItem(
                withTitle: "Nothing for today",
                action: nil,
                keyEquivalent: "")
            item.isEnabled = false
        }

        for event in sortedEvents {
            self.createEventItem(event: event)
        }
    }

    func createEventItem(event: EKEvent) {
        let now = Date()

        let eventTitle = String(event.title)

        let eventTimeFormatter = DateFormatter()
        eventTimeFormatter.dateFormat = "HH:mm"

        var eventStartTime = ""
        if event.isAllDay {
            eventStartTime = "All day"
        } else {
            eventStartTime = eventTimeFormatter.string(from: event.startDate)
        }

        // Event Item
        let itemTitle = "\(eventStartTime) - \(eventTitle)"
        let eventItem = self.item.menu!.addItem(
            withTitle: itemTitle,
            action: #selector(StatusBarItemControler.clickOnEvent(sender:)),
            keyEquivalent: "")
        let eventStatus = getEventStatus(event)
        if eventStatus != nil {
            if eventStatus == .declined {
                eventItem.attributedTitle = NSAttributedString(
                    string: itemTitle,
                    attributes: [NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.thick.rawValue])
            }
        }
        if event.endDate < now {
            eventItem.state = .on
            if !Defaults[.showEventDetails] {
                eventItem.isEnabled = false
            }
        } else if event.startDate < now, event.endDate > now {
            eventItem.state = .mixed
        } else {
            eventItem.state = .off
        }
        eventItem.representedObject = event

        if Defaults[.showEventDetails] {
            let eventMenu = NSMenu(title: "Item \(eventTitle) menu")
            eventItem.submenu = eventMenu

            // Title
            let titleItem = eventMenu.addItem(withTitle: eventTitle, action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(string: eventTitle, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 15)])
            eventMenu.addItem(NSMenuItem.separator())

            // Calendar
            if Defaults[.selectedCalendars].count > 1 {
                eventMenu.addItem(withTitle: "Calendar:", action: nil, keyEquivalent: "")
                eventMenu.addItem(withTitle: event.calendar.title, action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Duration
            if !event.isAllDay {
                let eventEndTime = eventTimeFormatter.string(from: event.endDate)
                let eventDurationMinutes = String(event.endDate.timeIntervalSince(event.startDate) / 60)
                let durationTitle = "\(eventStartTime) - \(eventEndTime) (\(eventDurationMinutes) minutes)"
                eventMenu.addItem(withTitle: durationTitle, action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Status
            if eventStatus != nil {
                var status: String
                switch eventStatus {
                case .accepted:
                    status = " 👍 Accepted"
                case .declined:
                    status = " 👎 Canceled"
                case .tentative:
                    status = " ☝️ Tentative"
                default:
                    status = " ❔ (\(String(describing: eventStatus))))"
                }
                eventMenu.addItem(withTitle: "Status: \(status)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Location
            if event.location != nil {
                eventMenu.addItem(withTitle: "Location:", action: nil, keyEquivalent: "")
                eventMenu.addItem(withTitle: "\(event.location!)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Organizer
            if let eventOrganizer = event.organizer {
                eventMenu.addItem(withTitle: "Organizer:", action: nil, keyEquivalent: "")
                let organizerName = eventOrganizer.name ?? ""
                eventMenu.addItem(withTitle: "\(organizerName)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Notes
            if event.hasNotes {
                let notes = cleanUpNotes(event.notes!)
                if notes.count > 0 {
                    eventMenu.addItem(withTitle: "Notes:", action: nil, keyEquivalent: "")
                    let item = eventMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.lineBreakMode = NSLineBreakMode.byWordWrapping
                    item.attributedTitle = NSAttributedString(string: notes, attributes: [NSAttributedString.Key.paragraphStyle: paragraphStyle])
                    eventMenu.addItem(NSMenuItem.separator())
                }
            }

            // Attendees
            if event.hasAttendees {
                let attendees: [EKParticipant] = event.attendees!
                let count = attendees.filter { $0.participantType == .person }.count
                let sortedAttendees = attendees.sorted {
                    if $0.participantRole.rawValue != $1.participantRole.rawValue {
                        return $0.participantRole.rawValue < $1.participantRole.rawValue
                    } else {
                        return $0.participantStatus.rawValue < $1.participantStatus.rawValue
                    }
                }
                eventMenu.addItem(withTitle: "Attendees (\(count)):", action: nil, keyEquivalent: "")
                for attendee in sortedAttendees {
                    if attendee.participantType != .person {
                        continue
                    }
                    var attributes: [NSAttributedString.Key: Any] = [:]

                    var name = attendee.name!

                    if attendee.isCurrentUser {
                        name = "\(name) (you)"
                    }

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
                        attributes[NSAttributedString.Key.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
                    case .tentative:
                        status = " [tentative]"
                    case .pending:
                        status = " [?]"
                    default:
                        status = ""
                    }

                    let itemTitle = "- \(name)\(roleMark) \(status)"
                    let item = eventMenu.addItem(withTitle: itemTitle, action: nil, keyEquivalent: "")
                    item.attributedTitle = NSAttributedString(string: itemTitle, attributes: attributes)
                }
            }
        }
    }

    func createPreferencesSection() {
        self.item.menu!.addItem(
            withTitle: "Preferences",
            action: #selector(AppDelegate.openPrefecencesWindow),
            keyEquivalent: "")
        self.item.menu!.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quit),
            keyEquivalent: "")
    }

    @objc func clickOnEvent(sender: NSMenuItem) {
        NSLog("Click on event (\(sender.title))!")
        let event: EKEvent = sender.representedObject as! EKEvent
        openEvent(event)
    }
}

func createEventStatusString(_ event: EKEvent) -> String {
    let nextMinute = Date().addingTimeInterval(60)
    var eventTitle = "Meeting"
    if Defaults[.showEventTitleInStatusBar] {
        eventTitle = String(event.title ?? "No title")
        if Defaults[.titleLength] != TitleLengthLimits.max, eventTitle.count > Int(Defaults[.titleLength]) {
            let index = eventTitle.index(eventTitle.startIndex, offsetBy: Int(Defaults[.titleLength]))
            eventTitle = String(eventTitle[...index])
            eventTitle += "..."
        }
    }
    var msg = ""
    if (event.startDate)! < nextMinute, (event.endDate)! > nextMinute {
        let eventEndTime = event.endDate.timeIntervalSinceNow
        let minutes = String(Int(eventEndTime) / 60)
        msg = " now (\(minutes) min left)"
    } else {
        let eventStartTime = event.startDate.timeIntervalSinceNow
        let minutes = Int(eventStartTime) / 60
        if minutes < 60 {
            msg = " in \(minutes) min"
        } else if minutes < 120 {
            let remainder = minutes % 60
            msg = " in 1 hour \(remainder) min"
        } else {
            let hours = minutes / 60
            msg = " in \(hours) hours"
        }
    }
    return "\(eventTitle)\(msg)"
}

func openEvent(_ event: EKEvent) {
    let eventTitle = event.title ?? "No title"
    if let notes = event.notes {
        let meetLink = getMatch(text: notes, regex: LinksRegex.meet)
        if let link = meetLink {
            if let meetURL = URL(string: link) {
                if Defaults[.useChromeForMeetLinks] {
                    openLinkInChrome(meetURL)
                } else {
                    openLinkInDefaultBrowser(meetURL)
                }
            }
        } else {
            NSLog("No meet link for event (\(eventTitle))")
            let zoomLink = getMatch(text: notes, regex: LinksRegex.zoom)
            if let link = zoomLink {
                if let zoomURL = URL(string: link) {
                    openLinkInDefaultBrowser(zoomURL)
                }
            }
            NSLog("No zoom link for event (\(eventTitle))")
        }
    } else {
        NSLog("No notes for event (\(eventTitle))")
    }
}

func getEventStatus(_ event: EKEvent) -> EKParticipantStatus? {
    if event.hasAttendees {
        if let currentUser = event.attendees!.first(where: { $0.isCurrentUser }) {
            return currentUser.participantStatus
        }
    }
    return nil
}
