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
class StatusBarItemControler: NSObject, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var statusItemMenu: NSMenu!
    var menuIsOpen = false

    let eventStore = EKEventStore()
    var calendars: [EKCalendar] = []

    weak var appdelegate: AppDelegate!

    func enableButtonAction() {
        let button: NSStatusBarButton = self.statusItem.button!
        button.target = self
        button.action = #selector(self.statusMenuBarAction)
        button.sendAction(on: [NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseUp, NSEvent.EventTypeMask.leftMouseDown])
        self.menuIsOpen = false
    }

    override
    init() {
        super.init()

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItemMenu = NSMenu(title: "MeetingBar in Status Bar Menu")
        statusItemMenu.delegate = self

        enableButtonAction()
    }

    @objc
    func menuWillOpen(_ menu: NSMenu) {
        NSLog("menu has been opened \(self.menuIsOpen) for menu \(menu)")
        self.menuIsOpen = true
    }

    @objc
    func menuDidClose(_ menu: NSMenu) {
        NSLog("menu will close - \(self.menuIsOpen) for menu \(menu)")
        // remove menu when closed so we can override left click behavior
        self.statusItem.menu = nil
        self.menuIsOpen = false
    }

    @objc
    func statusMenuBarAction(sender: NSStatusItem) {
        if !self.menuIsOpen && self.statusItem.menu == nil {
            let event = NSApp.currentEvent!
            NSLog("Event occured \(event.type.rawValue)")

            // Right button click
            if event.type == NSEvent.EventType.rightMouseUp {
                self.appdelegate.joinNextMeeting()
            } else if event.type == NSEvent.EventType.leftMouseDown || event.type == NSEvent.EventType.leftMouseUp {
                // show the menu as normal
                self.statusItem.menu = self.statusItemMenu
                self.statusItem.button?.performClick(nil) // ...and click

            }
        }
    }

    func setAppDelegate(appdelegate: AppDelegate) {
        self.appdelegate = appdelegate
    }

    func loadCalendars() {
        calendars = eventStore.getMatchedCalendars(ids: Defaults[.selectedCalendarIDs])
        updateTitle()
        updateMenu()
    }

    func updateTitle() {
        var title = "MeetingBar"
        var time = ""
        var nextEvent: EKEvent!
        if !calendars.isEmpty {
            nextEvent = eventStore.getNextEvent(calendars: calendars)
            if let nextEvent = nextEvent {
                (title, time) = createEventStatusString(nextEvent)
                if Defaults[.joinEventNotification] {
                    scheduleEventNotification(nextEvent)
                }
            } else {
                if Defaults[.joinEventNotification] {
                    removePendingNotificationRequests()
                }
                title = "🏁"
            }
        } else {
            NSLog("No loaded calendars")
        }

        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                button.image = nil
                button.title = ""
                if title == "🏁" {
                    switch Defaults[.eventTitleIconFormat] {
                    case .appicon:
                        button.image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                    default:
                        button.image = NSImage(named: "iconCalendarCheckmark")
                    }
                    button.image?.size = NSSize(width: 16, height: 16)
                } else if title == "MeetingBar" {
                    button.image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                    button.image?.size = NSSize(width: 16, height: 16)
                }

                if button.image == nil {
                    if Defaults[.eventTitleIconFormat] != EventTitleIconFormat.none {
                        let image: NSImage
                        if Defaults[.eventTitleIconFormat] == EventTitleIconFormat.eventtype {
                            image = self.getMeetingIcon(nextEvent)
                        } else {
                            image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                        }

                        button.image = image
                        button.image?.size = NSSize(width: 16, height: 16)
                        if image.name() == "no_online_session" {
                            button.imagePosition = .noImage
                        } else {
                            button.imagePosition = .imageLeft
                        }
                    }

                    // create an NSMutableAttributedString that we'll append everything to
                    let menuTitle = NSMutableAttributedString()
                    let eventStatus = getEventParticipantStatus(nextEvent)

                    if Defaults[.eventTimeFormat] != EventTimeFormat.show_under_title || Defaults[.eventTitleFormat] == .none {
                        var eventTitle = title
                        if Defaults[.eventTimeFormat] == EventTimeFormat.show {
                            eventTitle += " " + time
                        }

                        var styles = [NSAttributedString.Key: Any]()
                        styles[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: 13)


                        if eventStatus == .pending && Defaults[.showPendingEvents] == PendingEventsAppereance.show_inactive {
                            styles[NSAttributedString.Key.foregroundColor] = NSColor.lightGray
                        } else if eventStatus == .pending && Defaults[.showPendingEvents] == PendingEventsAppereance.show_underlined {
                            styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
                        }

                        menuTitle.append(NSAttributedString(string: eventTitle, attributes: styles))
                    } else {
                        let paragraphStyle = NSMutableParagraphStyle()
                        paragraphStyle.lineHeightMultiple = 0.7
                        paragraphStyle.alignment = .center

                        var styles = [NSAttributedString.Key: Any]()
                        styles[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: 12)
                        styles[NSAttributedString.Key.baselineOffset] = -3

                        if eventStatus == .pending && Defaults[.showPendingEvents] == PendingEventsAppereance.show_inactive {
                            styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
                        } else if eventStatus == .pending && Defaults[.showPendingEvents] == PendingEventsAppereance.show_underlined {
                            styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
                        }

                        menuTitle.append(NSAttributedString(string: title, attributes: styles))

                        menuTitle.append(NSAttributedString(string: "\n" + time, attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 9), NSAttributedString.Key.foregroundColor: NSColor.lightGray]))


                        menuTitle.addAttributes([NSAttributedString.Key.paragraphStyle: paragraphStyle], range: NSRange(location: 0, length: menuTitle.length))
                    }

                    button.attributedTitle = menuTitle
                    if nextEvent != nil {
                        button.toolTip = nextEvent.title
                    }
                }
            }
        }
    }

    func updateMenu() {
        self.statusItemMenu.autoenablesItems = false
        self.statusItemMenu.removeAllItems()

        if !self.calendars.isEmpty {
            let today = Date()
            switch Defaults[.showEventsForPeriod] {
            case .today:
                self.createDateSection(date: today, title: "Today")
            case .today_n_tomorrow:
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
                self.createDateSection(date: today, title: "Today")
                self.statusItemMenu.addItem(NSMenuItem.separator())
                self.createDateSection(date: tomorrow, title: "Tomorrow")
            }
        } else {
            let text = "Select calendars in preferences\nto see your meetings"
            let item = self.statusItemMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = NSLineBreakMode.byWordWrapping
            item.attributedTitle = NSAttributedString(string: text, attributes: [NSAttributedString.Key.paragraphStyle: paragraphStyle])
            item.isEnabled = false
        }
        self.statusItemMenu.addItem(NSMenuItem.separator())
        self.createJoinSection()
        self.statusItemMenu.addItem(NSMenuItem.separator())

        self.createPreferencesSection()
    }

    func createJoinSection() {
        if !calendars.isEmpty {
            let nextEvent = eventStore.getNextEvent(calendars: calendars)
            if nextEvent != nil {
                let joinItem = self.statusItemMenu.addItem(
                    withTitle: "Join next event meeting",
                    action: #selector(AppDelegate.joinNextMeeting),
                    keyEquivalent: ""
                )
                joinItem.setShortcut(for: .joinEventShortcut)
            }
        }


        let createEventItem = NSMenuItem()
        createEventItem.title = "Create meeting"
        createEventItem.action = #selector(AppDelegate.createMeeting)
        createEventItem.keyEquivalent = ""
        createEventItem.setShortcut(for: .createMeetingShortcut)

        self.statusItemMenu.addItem(createEventItem)

        if !Defaults[.bookmarks].isEmpty {
            self.statusItemMenu.addItem(NSMenuItem.separator())

            let bookmarksItem = self.statusItemMenu.addItem(
                withTitle: "Bookmarks",
                action: nil,
                keyEquivalent: ""
            )

            var bookmarksMenu: NSMenu

            if Defaults[.bookmarks].count > 3 {
                bookmarksMenu = NSMenu(title: "Bookmarks menu")
                bookmarksItem.submenu = bookmarksMenu
            } else {
                bookmarksItem.attributedTitle = NSAttributedString(string: "Bookmarks", attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 13)])
                bookmarksItem.isEnabled = false
                bookmarksMenu = self.statusItemMenu
            }

            for bookmark in Defaults[.bookmarks] {
                let bookmarkItem = bookmarksMenu.addItem(
                    withTitle: bookmark.name,
                    action: #selector(AppDelegate.joinBookmark),
                    keyEquivalent: "")

                bookmarkItem.representedObject = bookmark
            }
        }
    }

    func createDateSection(date: Date, title: String) {
        let events: [EKEvent] = eventStore.loadEventsForDate(calendars: calendars, date: date)

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM"
        let dateString = dateFormatter.string(from: date)
        let dateTitle = "\(title) (\(dateString)):"
        let titleItem = self.statusItemMenu.addItem(
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
            let item = self.statusItemMenu.addItem(
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
        case .some(.zoom), .some(.zoomgov), .some(.zoom_native):
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
        case .some(.youtube):
            image = NSImage(named: "youtube_icon")!
            image!.size = NSSize(width: 16, height: 16)

        // tested and verified
        case .none:
            image = NSImage(named: "no_online_session")!
            image!.size = NSSize(width: 16, height: 16)

        case .some(.vonageMeetings):
            image = NSImage(named: "online_meeting_icon")!
            image!.size = NSSize(width: 16, height: 16)

        case .some(.meetStream):
            image = NSImage(named: "online_meeting_icon")!
            image!.size = NSSize(width: 16, height: 16)

        default:
            break
        }

        return image!
    }

    func createEventItem(event: EKEvent) {
        let eventParticipantStatus = getEventParticipantStatus(event)
        let eventStatus = event.status

        let now = Date()

        if eventParticipantStatus == .declined || eventStatus == .canceled, Defaults[.declinedEventsAppereance] == .hide {
            return
        }

        if event.endDate < now, Defaults[.pastEventsAppereance] == .hide {
            return
        }

        if !event.hasAttendees, Defaults[.personalEventsAppereance] == .hide {
            return
        }

        let eventTitle: String

        if Defaults[.shortenEventTitle] {
            eventTitle = shortenTitleForMenu(event: event)
        } else {
            eventTitle = String(event.title)
        }

        let eventTimeFormatter = DateFormatter()

        switch Defaults[.timeFormat] {
        case .am_pm:
            eventTimeFormatter.dateFormat = "hh:mm a"
        case .military:
            eventTimeFormatter.dateFormat = "HH:mm"
        }

        var eventStartTime = ""
        var eventEndTime = ""
        if event.isAllDay {
            eventStartTime = "All day"
            eventEndTime = "\t"
        } else {
            eventStartTime = eventTimeFormatter.string(from: event.startDate)
            eventEndTime = eventTimeFormatter.string(from: event.endDate)
        }


        let itemTitle: String
        if Defaults[.showEventEndTime] {
            itemTitle = "\(eventStartTime) \t \(eventEndTime) \t \(eventTitle)"
        } else {
            itemTitle = "\(eventStartTime) \t \(eventTitle)"
        }

        // Event Item

        let eventItem = NSMenuItem()
        eventItem.title = itemTitle
        eventItem.action = #selector(AppDelegate.clickOnEvent(sender:))
        eventItem.keyEquivalent = ""

        if Defaults[.showMeetingServiceIcon] {
            eventItem.image = getMeetingIcon(event)
        }

        var shouldShowAsActive = true
        var styles = [NSAttributedString.Key: Any]()

        if eventParticipantStatus == .declined || eventStatus == .canceled {
            if Defaults[.declinedEventsAppereance] == .show_inactive {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
            } else {
                styles[NSAttributedString.Key.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
            }
            shouldShowAsActive = false
        }

        if eventParticipantStatus == .pending {
            if Defaults[.showPendingEvents] == PendingEventsAppereance.show_inactive {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
            } else if Defaults[.showPendingEvents] == PendingEventsAppereance.show_underlined {
                styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
            }
        }

        if !event.hasAttendees, Defaults[.personalEventsAppereance] == .show_inactive {
            styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
            shouldShowAsActive = false
        }


        if event.endDate < now, eventStatus != .canceled {
            eventItem.state = .on
            eventItem.onStateImage = nil
            if Defaults[.pastEventsAppereance] == .show_inactive {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
                styles[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: 14)

                eventItem.attributedTitle = NSAttributedString(
                    string: itemTitle,
                    attributes: styles
                )
            }
        } else if event.startDate < now, event.endDate > now, eventStatus != .canceled {
            eventItem.state = .mixed

            // if highlightRunningEvent
            eventItem.mixedStateImage = nil

            // create an NSMutableAttributedString that we'll append everything to
            let eventTitle = NSMutableAttributedString()

            if shouldShowAsActive && Defaults[.showPendingEvents] != PendingEventsAppereance.show_underlined {
                // add the NSTextAttachment wrapper to our full string, then add some more text.
                styles[NSAttributedString.Key.font] = NSFont.boldSystemFont(ofSize: 14)
            } else {
                styles[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: 14)
            }

            eventTitle.append(NSAttributedString(string: itemTitle, attributes: styles))

            if shouldShowAsActive {
                // create our NSTextAttachment
                let runningImage = NSTextAttachment()
                runningImage.image = NSImage(named: "running_icon")
                runningImage.image?.size = NSSize(width: 16, height: 16)

                // wrap the attachment in its own attributed string so we can append it
                let runningIcon = NSAttributedString(attachment: runningImage)
                eventTitle.append(NSAttributedString(string: " "))
                eventTitle.append(runningIcon)
            }

            eventItem.attributedTitle = eventTitle
        } else {
            eventItem.state = .off
            eventItem.offStateImage = nil
            eventItem.attributedTitle = NSAttributedString(string: itemTitle, attributes: styles)
        }

        self.statusItemMenu.addItem(eventItem)
        eventItem.representedObject = event

        if Defaults[.showEventDetails] {
            let eventMenu = NSMenu(title: "Item \(eventTitle) menu")
            eventItem.submenu = eventMenu

            // Title
            let titleItem = eventMenu.addItem(withTitle: event.title, action: nil, keyEquivalent: "")
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
            if eventParticipantStatus != nil {
                var status: String
                switch eventParticipantStatus {
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
                    if let eventStatus = eventParticipantStatus {
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
        } else {
            eventItem.toolTip = event.title
        }
    }

    func createPreferencesSection() {
        self.statusItemMenu.addItem(
            withTitle: "Preferences",
            action: #selector(AppDelegate.openPrefecencesWindow),
            keyEquivalent: ","
        )

        self.statusItemMenu.addItem(
            withTitle: "Quit MeetingBar",
            action: #selector(AppDelegate.quit),
            keyEquivalent: "q"
        )
    }
}

func shortenTitleForSystembar(event: EKEvent) -> String {
    var eventTitle = String(event.title ?? "No title").trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
    if eventTitle.count > Defaults[.statusbarEventTitleLength] {
        let index = eventTitle.index(eventTitle.startIndex, offsetBy: Defaults[.statusbarEventTitleLength] - 1)
        eventTitle = String(eventTitle[...index]).trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
        eventTitle += "..."
    }

    return eventTitle
}

func shortenTitleForMenu(event: EKEvent) -> String {
    var eventTitle = String(event.title ?? "No title").trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
    if eventTitle.count > Int(Defaults[.menuEventTitleLength]) {
        let index = eventTitle.index(eventTitle.startIndex, offsetBy: Int(Defaults[.menuEventTitleLength]) - 1)
        eventTitle = String(eventTitle[...index]).trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
        eventTitle += "..."
    }

    return eventTitle
}


func createEventStatusString(_ event: EKEvent) -> (String, String) {
    var eventTime: String

    var eventTitle: String
    switch Defaults[.eventTitleFormat] {
    case .show:
        eventTitle = shortenTitleForSystembar(event: event)
    case .dot:
        eventTitle = "•"
    case .none:
        eventTitle = ""
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
        eventTime = "now (\(formattedTimeLeft) left)"
    } else {
        eventTime = "in \(formattedTimeLeft)"
    }
    return (eventTitle, eventTime)
}

func openEvent(_ event: EKEvent) {
    let eventTitle = event.title ?? "No title"
    if let meeting = getMeetingLink(event) {
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
        openMeetingURL(meeting.service, meeting.url)
    } else {
        sendNotification("Epp! Can't join the \(eventTitle)", "Link not found, or your meeting service is not yet supported")
    }
}

func getEventParticipantStatus(_ event: EKEvent) -> EKParticipantStatus? {
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
        let browser = Defaults[.browserForMeetLinks]
        url.openIn(browser: browser)

    case .teams:
        if Defaults[.useAppForTeamsLinks] {
            var teamsAppURL = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            teamsAppURL.scheme = "msteams"
            let result = teamsAppURL.url!.openInDefaultBrowser()
            if !result {
                sendNotification("Oops! Unable to open the link in Microsoft Teams app", "Make sure you have Microsoft Teams app installed, or change the app in the preferences.")
                url.openInDefaultBrowser()
            }
        } else {
            url.openInDefaultBrowser()
        }
    case .zoom:
        if Defaults[.useAppForZoomLinks] {
            let urlString = url.absoluteString.replacingOccurrences(of: "?", with: "&").replacingOccurrences(of: "/j/", with: "/join?confno=")
            var zoomAppUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomAppUrl.scheme = "zoommtg"
            let result = zoomAppUrl.url!.openInDefaultBrowser()
            if !result {
                sendNotification("Oops! Unable to open the link in Zoom app", "Make sure you have Zoom app installed, or change the app in the preferences.")
                url.openInDefaultBrowser()
            }
        } else {
            url.openInDefaultBrowser()
        }
    case .zoom_native:
        let result = url.openInDefaultBrowser()
        if !result {
            sendNotification("Oops! Unable to open the native link in Zoom app", "Make sure you have Zoom app installed, or change the app in the preferences.")

            let urlString = url.absoluteString.replacingFirstOccurrence(of: "&", with: "?").replacingOccurrences(of: "/join?confno=", with: "/j/")
            var zoomBrowserUrl = URLComponents(url: URL(string: urlString)!, resolvingAgainstBaseURL: false)!
            zoomBrowserUrl.scheme = "https"
            zoomBrowserUrl.url!.openInDefaultBrowser()
        }
    case .facetime:
        NSWorkspace.shared.open(URL(string: "facetime://" + url.absoluteString)!)
    case .facetimeaudio:
        NSWorkspace.shared.open(URL(string: "facetime-audio://" + url.absoluteString)!)
    case .phone:
        NSWorkspace.shared.open(URL(string: "tel://" + url.absoluteString)!)
    default:
        url.openInDefaultBrowser()
    }
}
