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
        item = NSStatusBar.system.statusItem(
                withLength: NSStatusItem.variableLength
        )
        let statusBarMenu = NSMenu(title: "MeetingBar in Status Bar Menu")
        item.menu = statusBarMenu
    }

    func loadCalendars() {
        calendars = eventStore.getMatchedCalendars(ids: Defaults[.selectedCalendarIDs])
        updateTitle()
        updateMenu()
    }

    func updateTitle() {
        var title = "MeetingBar"
        if !calendars.isEmpty {
            let nextEvent = eventStore.getNextEvent(calendars: calendars)
            if let nextEvent = nextEvent {
                title = createEventStatusString(nextEvent)
                if Defaults[.joinEventNotification] {
                    scheduleEventNotification(nextEvent)
                }
            } else {
                title = "🏁"
            }
        } else {
            NSLog("No loaded calendars")
        }
        DispatchQueue.main.async {
            if let button = self.item.button {
                button.image = nil
                button.title = ""
                if title == "🏁" {
                    button.image = NSImage(named: "iconCalendarCheckmark")
                } else if title == "MeetingBar" {
                    button.image = NSImage(named: "iconCalendar")
                }
                //
                if button.image == nil {
                    button.title = "\(title)"
                }
            }
        }
    }

    func updateMenu() {
        if let statusBarMenu = item.menu {
            statusBarMenu.autoenablesItems = false
            statusBarMenu.removeAllItems()

            if !calendars.isEmpty {
                let today = Date()
                switch Defaults[.showEventsForPeriod] {
                case .today:
                    createDateSection(date: today, title: "Today")
                case .today_n_tomorrow:
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
                    createDateSection(date: today, title: "Today")
                    statusBarMenu.addItem(NSMenuItem.separator())
                    createDateSection(date: tomorrow, title: "Tomorrow")
                }
            } else {
                let text = "Select calendars in preferences\nto see your meetings"
                let item = self.item.menu!.addItem(withTitle: "", action: nil, keyEquivalent: "")
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = NSLineBreakMode.byWordWrapping
                item.attributedTitle = NSAttributedString(string: text, attributes: [NSAttributedString.Key.paragraphStyle: paragraphStyle])
                item.isEnabled = false
            }
            statusBarMenu.addItem(NSMenuItem.separator())
            createJoinSection()
            statusBarMenu.addItem(NSMenuItem.separator())

            createPreferencesSection()
        }
    }

    func createJoinSection() {
        if !calendars.isEmpty {
            let nextEvent = eventStore.getNextEvent(calendars: calendars)
            if nextEvent != nil {
                let joinItem = item.menu!.addItem(
                        withTitle: "Join next event meeting",
                        action: #selector(AppDelegate.joinNextMeeting),
                        keyEquivalent: ""
                )
                joinItem.setShortcut(for: .joinEventShortcut)
            }
        }
        let createItem = item.menu!.addItem(
                withTitle: "Create meeting",
                action: #selector(AppDelegate.createMeeting),
                keyEquivalent: ""
        )
        createItem.setShortcut(for: .createMeetingShortcut)
    }

    func createDateSection(date: Date, title: String) {
        let events: [EKEvent] = eventStore.loadEventsForDate(calendars: calendars, date: date)

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM"
        let dateString = dateFormatter.string(from: date)
        let dateTitle = "\(title) (\(dateString)):"
        let titleItem = item.menu!.addItem(
                withTitle: dateTitle,
                action: nil,
                keyEquivalent: ""
        )
        titleItem.attributedTitle = NSAttributedString(string: dateTitle, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 13)])
        titleItem.isEnabled = false

        // Events
        let sortedEvents = events.sorted {
            $0.startDate < $1.startDate
        }
        if sortedEvents.isEmpty {
            let item = self.item.menu!.addItem(
                    withTitle: "Nothing for \(title.lowercased())",
                    action: nil,
                    keyEquivalent: ""
            )
            item.isEnabled = false
        }
        for event in sortedEvents {
            createEventItem(event: event)
        }
    }

    func createEventItem(event: EKEvent) {
        let eventStatus = getEventStatus(event)

        let now = Date()

        if eventStatus == .declined, Defaults[.declinedEventsAppereance] == .hide {
            return
        }

        if event.endDate < now, Defaults[.pastEventsAppereance] == .hide {
            return
        }

        if !event.hasAttendees, Defaults[.personalEventsAppereance] == .hide {
            return
        }

        let eventTitle = String(event.title)

        let eventTimeFormatter = DateFormatter()

        switch Defaults[.timeFormat] {
        case .am_pm:
            eventTimeFormatter.dateFormat = "h:mm a"
        case .military:
            eventTimeFormatter.dateFormat = "HH:mm"
        }

        var eventStartTime = ""
        if event.isAllDay {
            eventStartTime = "All day"
        } else {
            eventStartTime = eventTimeFormatter.string(from: event.startDate)
        }

        // Event Item
        let itemTitle = "\(eventStartTime) - \(eventTitle)"
        let eventItem = item.menu!.addItem(
                withTitle: itemTitle,
                action: #selector(AppDelegate.clickOnEvent(sender:)),
                keyEquivalent: ""
        )

        if eventStatus == .declined {
            eventItem.attributedTitle = NSAttributedString(
                    string: itemTitle,
                    attributes: [NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.thick.rawValue]
            )
        }

        if !event.hasAttendees, Defaults[.personalEventsAppereance] == .show_inactive {
            eventItem.attributedTitle = NSAttributedString(
                string: itemTitle,
                attributes: [NSAttributedString.Key.foregroundColor: NSColor.disabledControlTextColor]
            )
        }

        if event.endDate < now {
            eventItem.state = .on
            if Defaults[.pastEventsAppereance] == .show_inactive {
                eventItem.attributedTitle = NSAttributedString(
                    string: itemTitle,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.disabledControlTextColor]
                )
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
            if Defaults[.selectedCalendarIDs].count > 1 {
                eventMenu.addItem(withTitle: "Calendar: \(event.calendar.title)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Duration
            if !event.isAllDay {
                let eventEndTime = eventTimeFormatter.string(from: event.endDate)
                let eventDurationMinutes = String(Int(event.endDate.timeIntervalSince(event.startDate) / 60))
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
                case .pending:
                    status = " ⏳ Pending"
                case .unknown:
                    status = " ❔ Unknown"
                default:
                    if let eventStatus = eventStatus {
                        status = " ❔ (\(String(describing: eventStatus)))"
                    } else {
                        status = " ❔ (Unknown)"
                    }
                }
                eventMenu.addItem(withTitle: "Status: \(status)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Location
            if let location = event.location {
                eventMenu.addItem(withTitle: "Location:", action: nil, keyEquivalent: "")
                eventMenu.addItem(withTitle: "\(location)", action: nil, keyEquivalent: "")
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
                let notes = cleanUpNotes(event.notes ?? "")
                if !notes.isEmpty {
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
                let attendees: [EKParticipant] = event.attendees ?? []
                let count = attendees.filter {
                    $0.participantType == .person
                }.count
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

                    var name = attendee.name ?? "No name attendee"

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
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Open in App
            let openItem = eventMenu.addItem(withTitle: "Open in Calendar App", action: #selector(AppDelegate.openEventInCalendar), keyEquivalent: "")
            openItem.representedObject = event.eventIdentifier
        }
    }

    func createPreferencesSection() {
        item.menu!.addItem(
                withTitle: "Preferences",
                action: #selector(AppDelegate.openPrefecencesWindow),
                keyEquivalent: ","
        )
        item.menu!.addItem(
                withTitle: "Quit",
                action: #selector(AppDelegate.quit),
                keyEquivalent: "q"
        )
    }
}

func createEventStatusString(_ event: EKEvent) -> String {
    var eventStatus: String

    var eventTitle: String
    switch Defaults[.eventTitleFormat] {
    case .show:
        eventTitle = String(event.title ?? "No title")
                .trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
        if eventTitle.count > Int(Defaults[.titleLength]) {
            let index = eventTitle.index(eventTitle.startIndex, offsetBy: Int(Defaults[.titleLength]) - 1)
            eventTitle = String(eventTitle[...index])
                    .trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
            eventTitle += "..."
        }
    case .dot:
        eventTitle = "•"
    }

    var isActiveEvent: Bool

    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = [.minute, .hour, .day]

    var eventDate: Date
    let now = Date()
    let nextMinute = Date().addingTimeInterval(60)
    if (event.startDate)! < nextMinute, (event.endDate)! > nextMinute {
        isActiveEvent = true
        eventDate = event.endDate
    } else {
        isActiveEvent = false
        eventDate = event.startDate
    }
    let formattedTimeLeft = formatter.string(from: now, to: eventDate)!

    if isActiveEvent {
        eventStatus = "\(eventTitle) now (\(formattedTimeLeft) left)"
    } else {
        eventStatus = "\(eventTitle) in \(formattedTimeLeft)"
    }
    return eventStatus
}

func openEvent(_ event: EKEvent) {
    let eventTitle = event.title ?? "No title"
    if let (service, url) = getMeetingLink(event) {
        if Defaults[.runJoinEventScript], Defaults[.joinEventScriptLocation] != nil {
            if let url = Defaults[.joinEventScriptLocation]?.appendingPathComponent("joinEventScript.scpt") {
                print("URL: \(url)")
                let task = try! NSUserAppleScriptTask(url: url)
                task.execute { error in
                    if let error = error {
                        sendNotification("AppleScript return error", error.localizedDescription)
                    }
                }
            }
        }
        openMeetingURL(service, url)
    } else {
        sendNotification("Epp! Can't join the \(eventTitle)", "Link not found, or your meeting service is not yet supported")
    }
}

func getEventStatus(_ event: EKEvent) -> EKParticipantStatus? {
    if event.hasAttendees {
        if let attendees = event.attendees {
            if let currentUser = attendees.first(where: { $0.isCurrentUser }) {
                return currentUser.participantStatus
            }
        }
    }
    return EKParticipantStatus.unknown
}



func openMeetingURL(_ service: MeetingServices?, _ url: URL) {
    switch service {
    case .meet:
        if Defaults[.useChromeForMeetLinks] {
            openLinkInChrome(url)
        } else {
            _ = openLinkInDefaultBrowser(url)
        }
    case .hangouts:
        if Defaults[.useChromeForHangoutsLinks] {
            openLinkInChrome(url)
        } else {
            _ = openLinkInDefaultBrowser(url)
        }
    case .teams:
        if Defaults[.useAppForTeamsLinks] {
            var teamsAppURL = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            teamsAppURL.scheme = "msteams"
            let result = openLinkInDefaultBrowser(teamsAppURL.url!)
            if !result {
                sendNotification("Oops! Unable to open the link in Microsoft Teams app", "Make sure you have Microsoft Teams app installed, or change the app in the preferences.")
                _ = openLinkInDefaultBrowser(url)
            }
        } else {
            _ = openLinkInDefaultBrowser(url)
        }
    case .zoom:
        if Defaults[.useAppForZoomLinks] {
            let urlString = url.absoluteString.replacingOccurrences(of: "?", with: "&").replacingOccurrences(of: "/j/", with: "/join?confno=")
            var teamsAppURL = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            teamsAppURL.scheme = "zoommtg"
            let result = openLinkInDefaultBrowser(teamsAppURL.url!)
            if !result {
                sendNotification("Oops! Unable to open the link in Zoom app", "Make sure you have Zoom app installed, or change the app in the preferences.")
                _ = openLinkInDefaultBrowser(url)
            }
        } else {
            _ = openLinkInDefaultBrowser(url)
        }
    default:
        _ = openLinkInDefaultBrowser(url)
    }
}
