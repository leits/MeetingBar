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

/**
 * creates the menu in the system status bar, creates the menu items and controls the whole lifecycle.
 */
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

        if !Defaults[.bookmarkMeetingURL].isEmpty {
            self.item.menu!.addItem(NSMenuItem.separator())
            let name = Defaults[.bookmarkMeetingName]
            let joinItem = self.item.menu!.addItem(
                withTitle: "Join \(name.isEmpty ? "bookmarked meeting" : name)",
                action: #selector(AppDelegate.joinBookmark),
                keyEquivalent: "")
            joinItem.setShortcut(for: .joinBookmarkShortcut)
        }
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
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }
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

    /**
     * try  to get the correct image for the specific
     */
    func getMeetingIcon(_ event: EKEvent) -> NSImage {
        var image: NSImage? = NSImage(named: "no_online_session")
        image!.size = NSSize(width: 16, height: 16)

        let result = getMeetingLink(event)
        switch result?.service {
        // tested and verified
        case .some(.teams):
            image = NSImage(named: "ms_teams_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.meet):
            image = NSImage(named: "google_meet_icon")!
            image!.size = NSSize(width: 16, height: 13.2)

        // tested and verified -> deprecated, can be removed because hangouts was replaced by google meet
        case .some(.hangouts):
            image = NSImage(named: "google_hangouts_icon")!
            image!.size = NSSize(width: 16, height: 17.8)

        // tested and verified
        case .some(.zoom), .some(.zoomgov):
            image = NSImage(named: "zoom_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.webex):
            image = NSImage(named: "webex_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.jitsi):
            image = NSImage(named: "jitsi_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.chime):
            image = NSImage(named: "amazon_chime_icon")!
            image!.size = NSSize(width: 16, height: 16)

        case .some(.ringcentral):
            image = NSImage(named: "online_meeting_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.gotomeeting):
            image = NSImage(named: "gotomeeting_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.gotowebinar):
            image = NSImage(named: "gotowebinar_icon")!
            image!.size = NSSize(width: 16, height: 16)

        case .some(.bluejeans):
            image = NSImage(named: "online_meeting_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.eight_x_eight):
            image = NSImage(named: "8x8_icon")!
            image!.size = NSSize(width: 16, height: 8)

        // tested and verified
        case .some(.demio):
            image = NSImage(named: "demio_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.join_me):
            image = NSImage(named: "joinme_icon")!
            image!.size = NSSize(width: 16, height: 10)

        // tested and verified
        case .some(.whereby):
            image = NSImage(named: "whereby_icon")!
            image!.size = NSSize(width: 16, height: 18)

        // tested and verified
        case .some(.uberconference):
            image = NSImage(named: "uberconference_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.blizz), .some(.teamviewer_meeting):
            image = NSImage(named: "teamviewer_meeting_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.vsee):
            image = NSImage(named: "vsee_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.starleaf):
            image = NSImage(named: "starleaf_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.duo):
            image = NSImage(named: "google_duo_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.voov):
            image = NSImage(named: "voov_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.skype):
            image = NSImage(named: "skype_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.skype4biz), .some(.skype4biz_selfhosted):
            image = NSImage(named: "skype_business_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.lifesize):
            image = NSImage(named: "lifesize_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .some(.facebook_workspace):
            image = NSImage(named: "facebook_workplace_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .none:
            image = NSImage(named: "no_online_session")!
            image!.size = NSSize(width: 16, height: 16)
        }

        return image!
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
        let eventItem = NSMenuItem()

        eventItem.title = itemTitle
        eventItem.action = #selector(AppDelegate.clickOnEvent(sender:))
        eventItem.keyEquivalent = ""

        if Defaults[.showMeetingServiceIcon] {
            let image: NSImage = getMeetingIcon(event)
            eventItem.image = image
        }

        item.menu!.addItem(eventItem)

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
        eventTitle = String(event.title ?? "No title").trimmingCharacters(in: .whitespaces)
        if eventTitle.count > Int(Defaults[.titleLength]) {
            let index = eventTitle.index(eventTitle.startIndex, offsetBy: Int(Defaults[.titleLength]))
            eventTitle = String(eventTitle[...index])
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
        switch Defaults[.useChromeForMeetLinks] {
        case .chrome:
            openLinkInChrome(url)
        case .chromium:
            openLinkInChromium(url)
        default:
            _ = openLinkInDefaultBrowser(url)
        }
    case .hangouts:
        switch Defaults[.useChromeForHangoutsLinks] {
        case .chrome:
            openLinkInChrome(url)
        case .chromium:
            openLinkInChromium(url)
        default:
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
            var zoomAppUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomAppUrl.scheme = "zoommtg"
            let result = openLinkInDefaultBrowser(zoomAppUrl.url!)
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
