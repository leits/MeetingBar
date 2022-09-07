//
//  StatusBarItemController.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import EventKit

import Defaults
import KeyboardShortcuts
import PromiseKit

/**
 * creates the menu in the system status bar, creates the menu items and controls the whole lifecycle.
 */
class StatusBarItemController: NSObject, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var statusItemMenu: NSMenu!
    var menuIsOpen = false
    var currentStatusBarEvent: MBEvent?

    var calendars: [MBCalendar] = []
    var events: [MBEvent] = []

    let isFantasticalInstalled = checkIsFantasticalInstalled()

    weak var appdelegate: AppDelegate!

    func enableButtonAction() {
        let button: NSStatusBarButton = statusItem.button!
        button.target = self
        button.action = #selector(statusMenuBarAction)
        button.sendAction(on: [NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseUp, NSEvent.EventTypeMask.leftMouseDown])
        menuIsOpen = false
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
    func menuWillOpen(_: NSMenu) {
        menuIsOpen = true
    }

    @objc
    func menuDidClose(_: NSMenu) {
        // remove menu when closed so we can override left click behavior
        statusItem.menu = nil
        menuIsOpen = false
    }

    @objc
    func statusMenuBarAction(sender _: NSStatusItem) {
        if !menuIsOpen, statusItem.menu == nil {
            let event = NSApp.currentEvent

            // Right button click
            if event?.type == NSEvent.EventType.rightMouseUp {
                joinNextMeeting()
            } else if event == nil || event?.type == NSEvent.EventType.leftMouseDown || event?.type == NSEvent.EventType.leftMouseUp {
                // show the menu as normal
                statusItem.menu = statusItemMenu
                statusItem.button?.performClick(nil) // ...and click
            }
        }
    }

    func setAppDelegate(appdelegate: AppDelegate) {
        self.appdelegate = appdelegate
    }

    func loadCalendars() {
        _ = appdelegate.eventStore.fetchAllCalendars().done { calendars in
            for calendar in calendars {
                calendar.selected = Defaults[.selectedCalendarIDs].contains(calendar.ID)
            }
            self.calendars = calendars
            self.loadEvents()
        }
    }

    func loadEvents() {
        let dateFrom = Calendar.current.startOfDay(for: Date())
        var dateTo: Date

        switch Defaults[.showEventsForPeriod] {
        case .today:
            dateTo = Calendar.current.date(byAdding: .day, value: 1, to: dateFrom)!
        case .today_n_tomorrow:
            dateTo = Calendar.current.date(byAdding: .day, value: 2, to: dateFrom)!
        }

        _ = appdelegate.eventStore.fetchEventsForDateRange(calendars: calendars.filter(\.selected), dateFrom: dateFrom, dateTo: dateTo).done { events in
            let filteredEvents = filterEvents(events)
            self.events = filteredEvents.sorted(by: { $0.startDate.compare($1.startDate) == .orderedAscending })
            self.updateTitle()
            self.updateMenu()
        }
    }

    func updateTitle() {
        enum NextEventState {
            case none
            case afterThreshold(MBEvent)
            case nextEvent(MBEvent)
        }

        var title = "MeetingBar"
        var time = ""
        var nextEvent: MBEvent!
        let nextEventState: NextEventState
        if !calendars.filter(\.selected).isEmpty {
            nextEvent = getNextEvent(events: events)
            nextEventState = {
                guard let nextEvent = nextEvent else {
                    return .none
                }
                if Calendar.current.isDateInTomorrow(nextEvent.startDate) && !Defaults[.includeTomorrowInStatusBar] {
                    return .none
                }

                guard Defaults[.showEventMaxTimeUntilEventEnabled] else {
                    return .nextEvent(nextEvent)
                }
                // Positive, if in the future. Negative, if already started.
                // Current or past events therefore don't get ignored.
                let timeUntilStart = nextEvent.startDate.timeIntervalSinceNow
                let thresholdInSeconds = TimeInterval(Defaults[.showEventMaxTimeUntilEventThreshold] * 60)
                return timeUntilStart < thresholdInSeconds ? .nextEvent(nextEvent) : .afterThreshold(nextEvent)
            }()
            switch nextEventState {
            case .none:
                if Defaults[.joinEventNotification] {
                    removePendingNotificationRequests()
                    removeDeliveredNotifications()
                }
                title = "🏁"
            case let .nextEvent(event):
                (title, time) = createEventStatusString(title: event.title, startDate: event.startDate, endDate: event.endDate)
                if Defaults[.joinEventNotification] {
                    scheduleEventNotification(event)
                }
            case let .afterThreshold(event):
                // Not sure, what the title should be in this case.
                title = "⏰"
                if Defaults[.joinEventNotification] {
                    scheduleEventNotification(event)
                }
            }
        } else {
            nextEventState = .none
        }
        if let button = statusItem.button {
            button.image = nil
            button.title = ""
            button.toolTip = nil
            if title == "🏁" {
                switch Defaults[.eventTitleIconFormat] {
                case .appicon:
                    button.image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                default:
                    button.image = NSImage(named: "iconCalendarCheckmark")
                }
                button.image?.size = NSSize(width: 16, height: 16)
            } else if title == "MeetingBar" {
                button.image = NSImage(named: "AppIcon")!
                button.image?.size = NSSize(width: 16, height: 16)
            } else if case .afterThreshold = nextEventState {
                switch Defaults[.eventTitleIconFormat] {
                case .appicon:
                    button.image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                default:
                    button.image = NSImage(named: "iconCalendar")
                }
            }

            if currentStatusBarEvent?.ID != nextEvent?.ID {
                if nextEvent == nil || (nextEvent!).startDate.timeIntervalSinceNow <= 0 {
                    currentStatusBarEvent = nextEvent
                    updateMenu()
                }
            }

            if button.image == nil {
                if Defaults[.eventTitleIconFormat] != EventTitleIconFormat.none {
                    let image: NSImage
                    if Defaults[.eventTitleIconFormat] == EventTitleIconFormat.eventtype {
                        image = getIconForMeetingService(nextEvent.meetingLink?.service)
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

                if Defaults[.eventTimeFormat] != EventTimeFormat.show_under_title || Defaults[.eventTitleFormat] == .none {
                    var eventTitle = title
                    if Defaults[.eventTimeFormat] == EventTimeFormat.show {
                        eventTitle += " " + time
                    }

                    var styles = [NSAttributedString.Key: Any]()
                    styles[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: 13)

                    if nextEvent.participationStatus == .pending, Defaults[.showPendingEvents] == PendingEventsAppereance.show_underlined {
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

                    if nextEvent.participationStatus == .pending, Defaults[.showPendingEvents] == PendingEventsAppereance.show_inactive {
                        styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
                    } else if nextEvent.participationStatus == .pending, Defaults[.showPendingEvents] == PendingEventsAppereance.show_underlined {
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

    /*
     * -----------------------
     * MARK: - MENU SECTIONS
     * ------------------------
     */

    func updateMenu() {
        statusItemMenu.autoenablesItems = false
        statusItemMenu.removeAllItems()

        if !calendars.filter(\.selected).isEmpty {
            let today = Date()
            switch Defaults[.showEventsForPeriod] {
            case .today:
                createDateSection(date: today, title: "status_bar_section_today".loco(), events: events)
            case .today_n_tomorrow:
                let todayEvents = events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: today) }
                createDateSection(date: today, title: "status_bar_section_today".loco(), events: todayEvents)

                statusItemMenu.addItem(NSMenuItem.separator())

                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
                let tomorrowEvents = events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: tomorrow) }
                createDateSection(date: tomorrow, title: "status_bar_section_tomorrow".loco(), events: tomorrowEvents)
            }
        } else {
            let text = "status_bar_empty_calendar_message".loco()
            let item = statusItemMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = NSLineBreakMode.byWordWrapping
            item.attributedTitle = NSAttributedString(string: text, attributes: [NSAttributedString.Key.paragraphStyle: paragraphStyle])
            item.isEnabled = false
        }
        statusItemMenu.addItem(NSMenuItem.separator())
        createJoinSection()

        if !Defaults[.bookmarks].isEmpty {
            statusItemMenu.addItem(NSMenuItem.separator())

            createBookmarksSection()
        }
        statusItemMenu.addItem(NSMenuItem.separator())

        createPreferencesSection()
    }

    /*
     * -----------------------
     * MARK: - Section: Date
     * ------------------------
     */

    func createDateSection(date: Date, title: String, events: [MBEvent]) {
        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM"
        dateFormatter.locale = I18N.instance.locale

        let dateString = dateFormatter.string(from: date)
        let dateTitle = "\(title) (\(dateString)):"
        let titleItem = statusItemMenu.addItem(
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
            let item = statusItemMenu.addItem(
                withTitle: "status_bar_section_date_nothing".loco(title.lowercased()),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
        }
        for event in sortedEvents {
            createEventItem(event: event, dateSection: date)
        }
    }

    func createEventItem(event: MBEvent, dateSection _: Date) {
        let eventStatus = event.status

        let now = Date()

        if event.participationStatus == .declined || eventStatus == .canceled, Defaults[.declinedEventsAppereance] == .hide {
            return
        }

        if event.endDate < now, Defaults[.pastEventsAppereance] == .hide {
            return
        }

        if event.attendees.count == 0, Defaults[.personalEventsAppereance] == .hide {
            return
        }

        let eventTitle: String

        if Defaults[.shortenEventTitle] {
            eventTitle = shortenTitle(title: event.title, offset: Defaults[.menuEventTitleLength])

        } else {
            eventTitle = String(event.title)
        }

        let eventTimeFormatter = DateFormatter()
        eventTimeFormatter.locale = I18N.instance.locale

        switch Defaults[.timeFormat] {
        case .am_pm:
            eventTimeFormatter.dateFormat = "h:mm a  "
        case .military:
            eventTimeFormatter.dateFormat = "HH:mm"
        }

        var eventStartTime = ""
        var eventEndTime = ""
        if event.isAllDay {
            eventStartTime = "status_bar_event_start_time_all_day".loco()
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
        eventItem.action = #selector(clickOnEvent(sender:))
        eventItem.target = self
        eventItem.keyEquivalent = ""

        if Defaults[.showMeetingServiceIcon] {
            eventItem.image = getIconForMeetingService(event.meetingLink?.service)
        }

        var shouldShowAsActive = true
        var styles = [NSAttributedString.Key: Any]()

        if event.participationStatus == .declined || eventStatus == .canceled {
            if Defaults[.declinedEventsAppereance] == .show_inactive {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
            } else {
                styles[NSAttributedString.Key.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
            }
            shouldShowAsActive = false
        }

        if !event.isAllDay, Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.show_inactive_without_meeting_link {
            if event.meetingLink == nil {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
                shouldShowAsActive = false
            }
        }

        if event.participationStatus == .pending {
            if Defaults[.showPendingEvents] == PendingEventsAppereance.show_inactive {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
            } else if Defaults[.showPendingEvents] == PendingEventsAppereance.show_underlined {
                styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
            }
        }

        if event.attendees.count == 0, Defaults[.personalEventsAppereance] == .show_inactive {
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

            if shouldShowAsActive, Defaults[.showPendingEvents] != PendingEventsAppereance.show_underlined {
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

        statusItemMenu.addItem(eventItem)
        eventItem.representedObject = event

        if Defaults[.showEventDetails] {
            let eventMenu = NSMenu(title: "Item \(eventTitle) menu")
            eventItem.submenu = eventMenu

            // Title
            let titleItem = eventMenu.addItem(withTitle: event.title, action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(string: eventTitle, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 15)])
            eventMenu.addItem(NSMenuItem.separator())

            // Status
            var status: String
            switch event.participationStatus {
            case .accepted:
                status = "status_bar_submenu_status_accepted".loco()
            case .declined:
                status = "status_bar_submenu_status_declined".loco()
            case .tentative:
                status = "status_bar_submenu_status_tentative".loco()
            case .pending:
                status = "status_bar_submenu_status_pending".loco()
            case .unknown:
                status = "status_bar_submenu_status_unknown".loco()
            default:
                status = "status_bar_submenu_status_default_extended".loco(String(describing: eventStatus))
            }
            eventMenu.addItem(withTitle: "status_bar_submenu_status_title".loco(status), action: nil, keyEquivalent: "")
            eventMenu.addItem(NSMenuItem.separator())

            // Duration
            if !event.isAllDay {
                let eventEndTime = eventTimeFormatter.string(from: event.endDate)
                let eventDurationMinutes = String(Int(event.endDate.timeIntervalSince(event.startDate) / 60))
                let durationTitle = "status_bar_submenu_duration_all_day".loco(eventStartTime, eventEndTime, eventDurationMinutes)
                eventMenu.addItem(withTitle: durationTitle, action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Calendar
            if Defaults[.selectedCalendarIDs].count > 1 {
                eventMenu.addItem(withTitle: "status_bar_submenu_calendar_title".loco(event.calendar.title), action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Location
            if let location = event.location {
                eventMenu.addItem(withTitle: "status_bar_submenu_location_title".loco(), action: nil, keyEquivalent: "")
                eventMenu.addItem(withTitle: "\(location)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Organizer
            if let eventOrganizer = event.organizer {
                let organizerName = eventOrganizer.name
                eventMenu.addItem(withTitle: "status_bar_submenu_organizer_title".loco(organizerName), action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Notes
            if var notes = event.notes {
                notes = cleanUpNotes(notes)
                if !notes.isEmpty {
                    eventMenu.addItem(withTitle: "status_bar_submenu_notes_title".loco(), action: nil, keyEquivalent: "")
                    let item = eventMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
                    item.view = createNSViewFromText(text: notes)

                    eventMenu.addItem(NSMenuItem.separator())
                }
            }

            // Attendees
            if !event.attendees.isEmpty {
                let sortedAttendees = event.attendees.sorted { $0.status.rawValue < $1.status.rawValue }
                eventMenu.addItem(withTitle: "status_bar_submenu_attendees_title".loco(sortedAttendees.count), action: nil, keyEquivalent: "")
                for attendee in sortedAttendees {
                    var attributes: [NSAttributedString.Key: Any] = [:]

                    var name = attendee.name

                    if attendee.isCurrentUser {
                        name = "status_bar_submenu_attendees_you".loco(name)
                    }

                    let roleMark = attendee.optional ? "*" : ""

                    var status: String
                    switch attendee.status {
                    case .declined:
                        status = ""
                        attributes[NSAttributedString.Key.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
                    case .tentative:
                        status = "status_bar_submenu_attendees_status_tentative".loco()
                    case .pending:
                        status = "status_bar_submenu_attendees_status_unknown".loco()
                    default:
                        status = ""
                    }

                    let itemTitle = "- \(name)\(roleMark) \(status)"
                    let item = eventMenu.addItem(withTitle: itemTitle, action: nil, keyEquivalent: "")
                    item.attributedTitle = NSAttributedString(string: itemTitle, attributes: attributes)
                }
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Copy meeting link
            let copyLinkItem = eventMenu.addItem(withTitle: "status_bar_submenu_copy_meeting_link".loco(), action: #selector(copyEventMeetingLink), keyEquivalent: "")
            copyLinkItem.target = self
            copyLinkItem.representedObject = event

            // Send email
            let emailItem = eventMenu.addItem(withTitle: "status_bar_submenu_email_attendees".loco(), action: #selector(emailAttendees), keyEquivalent: "")
            copyLinkItem.target = self
            emailItem.representedObject = event

            // Open in App
            let openItem = eventMenu.addItem(withTitle: "status_bar_submenu_open_in_calendar".loco(), action: #selector(openEventInCalendar), keyEquivalent: "")
            copyLinkItem.target = self
            openItem.representedObject = event.ID

            // Open in fanctastical if fantastical is installed
            if isFantasticalInstalled {
                let fantasticalItem = eventMenu.addItem(withTitle: "status_bar_submenu_open_in_fantastical".loco(), action: #selector(openEventInFantastical), keyEquivalent: "")
                copyLinkItem.target = self
                fantasticalItem.representedObject = event
            }
        } else {
            eventItem.toolTip = event.title
        }
    }

    /*
     * -----------------------
     * MARK: - Section: Join
     * ------------------------
     */

    func createJoinSection() {
        if !calendars.filter(\.selected).isEmpty {
            if let nextEvent = getNextEvent(events: events) {
                let now = Date()
                var itemTitle: String
                if nextEvent.startDate < now {
                    itemTitle = "status_bar_section_join_current_meeting".loco()
                } else {
                    itemTitle = "status_bar_section_join_next_meeting".loco()
                }

                let joinItem = statusItemMenu.addItem(
                    withTitle: itemTitle,
                    action: #selector(joinNextMeeting),
                    keyEquivalent: ""
                )
                joinItem.target = self
                joinItem.setShortcut(for: .joinEventShortcut)
            }
        }

        let createEventItem = NSMenuItem()
        createEventItem.title = "status_bar_section_join_create_meeting".loco()
        createEventItem.action = #selector(createMeetingAction)
        createEventItem.target = self
        createEventItem.keyEquivalent = ""
        createEventItem.setShortcut(for: .createMeetingShortcut)

        statusItemMenu.addItem(createEventItem)

        let quickActionsItem = statusItemMenu.addItem(
            withTitle: "status_bar_quick_actions".loco(),
            action: nil,
            keyEquivalent: ""
        )
        quickActionsItem.isEnabled = true

        quickActionsItem.submenu = NSMenu(title: "status_bar_quick_actions".loco())

        let openLinkFromClipboardItem = NSMenuItem()
        openLinkFromClipboardItem.title = "status_bar_section_join_from_clipboard".loco()
        openLinkFromClipboardItem.action = #selector(openLinkFromClipboardAction)
        openLinkFromClipboardItem.target = self
        openLinkFromClipboardItem.keyEquivalent = ""
        openLinkFromClipboardItem.setShortcut(for: .openClipboardShortcut)
        quickActionsItem.submenu!.addItem(openLinkFromClipboardItem)

        if Defaults[.eventTitleFormat] == .show {
            let toggleMeetingTitleVisibilityItem = NSMenuItem()
            if Defaults[.hideMeetingTitle] {
                toggleMeetingTitleVisibilityItem.title = "status_bar_show_meeting_names".loco()
            } else {
                toggleMeetingTitleVisibilityItem.title = "status_bar_hide_meeting_names".loco()
            }
            toggleMeetingTitleVisibilityItem.action = #selector(toggleMeetingTitleVisibility)
            toggleMeetingTitleVisibilityItem.target = self
            toggleMeetingTitleVisibilityItem.setShortcut(for: .toggleMeetingTitleVisibilityShortcut)
            quickActionsItem.submenu!.addItem(toggleMeetingTitleVisibilityItem)
        }

        let refreshSourcesItem = NSMenuItem()
        refreshSourcesItem.title = "status_bar_section_refresh_sources".loco()
        refreshSourcesItem.action = #selector(refreshSources)
        refreshSourcesItem.target = self
        refreshSourcesItem.keyEquivalent = ""
        quickActionsItem.submenu!.addItem(refreshSourcesItem)
    }

    /*
     * -----------------------
     * MARK: - Section: Bookmarks
     * ------------------------
     */

    func createBookmarksSection() {
        let bookmarksItem = statusItemMenu.addItem(
            withTitle: "status_bar_section_bookmarks_title".loco(),
            action: nil,
            keyEquivalent: ""
        )

        var bookmarksMenu: NSMenu

        if Defaults[.bookmarks].count > 3 {
            bookmarksMenu = NSMenu(title: "status_bar_section_bookmarks_menu".loco())
            bookmarksItem.submenu = bookmarksMenu
        } else {
            bookmarksItem.attributedTitle = NSAttributedString(string: "status_bar_section_bookmarks_title".loco(), attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 13)])
            bookmarksItem.isEnabled = false
            bookmarksMenu = statusItemMenu
        }

        for bookmark in Defaults[.bookmarks] {
            let bookmarkItem = bookmarksMenu.addItem(
                withTitle: bookmark.name,
                action: #selector(joinBookmark),
                keyEquivalent: ""
            )
            bookmarkItem.target = self
            bookmarkItem.representedObject = bookmark
        }
    }

    /*
     * -----------------------
     * MARK: - Section: Preferences
     * ------------------------
     */

    func createPreferencesSection() {
        let showChangelogItem = compareVersions(Defaults[.appVersion], Defaults[.lastRevisedVersionInChangelog])

        if showChangelogItem {
            let changelogItem = statusItemMenu.addItem(
                withTitle: "status_bar_whats_new".loco(),
                action: #selector(AppDelegate.openChangelogWindow),
                keyEquivalent: ""
            )
            changelogItem.image = NSImage(named: NSImage.statusAvailableName)
        }

        statusItemMenu.addItem(
            withTitle: "status_bar_preferences".loco(),
            action: #selector(AppDelegate.openPrefecencesWindow),
            keyEquivalent: ","
        )

        statusItemMenu.addItem(
            withTitle: "status_bar_quit".loco(),
            action: #selector(AppDelegate.quit),
            keyEquivalent: "q"
        )
    }

    /*
     * -----------------------
     * MARK: - Actions
     * ------------------------
     */

    @objc
    private func createMeetingAction() {
        createMeeting()
    }

    @objc
    func joinNextMeeting() {
        if let nextEvent = getNextEvent(events: events) {
            NSLog("Join next event")
            nextEvent.openMeeting()
        } else {
            NSLog("No next event")
            sendNotification("next_meeting_empty_title".loco(), "next_meeting_empty_message".loco())
        }
    }

    @objc
    func openLinkFromClipboardAction() {
        openLinkFromClipboard()
    }

    @objc
    func toggleMeetingTitleVisibility() {
        Defaults[.hideMeetingTitle].toggle()
    }

    @objc
    func refreshSources() {
        appdelegate.eventStore.refreshSources()
        loadCalendars()
    }

    @objc
    func joinBookmark(sender: NSMenuItem) {
        NSLog("Called to join bookmark")
        if let bookmark: Bookmark = sender.representedObject as? Bookmark {
            openMeetingURL(bookmark.service, bookmark.url, nil)
        }
    }

    @objc
    func clickOnEvent(sender: NSMenuItem) {
        NSLog("Click on event (\(sender.title))!")
        if let event: MBEvent = sender.representedObject as? MBEvent {
            event.openMeeting()
        }
    }

    @objc
    func openEventInCalendar(sender: NSMenuItem) {
        if let identifier = sender.representedObject as? String {
            let url = URL(string: "ical://ekevent/\(identifier)")!
            url.openInDefaultBrowser()
        }
    }

    @objc
    func copyEventMeetingLink(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            if let meetingLink = event.meetingLink {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(meetingLink.url.absoluteString, forType: .string)
            } else {
                sendNotification("status_bar_error_link_missed_title".loco(event.title), "status_bar_error_link_missed_message".loco())
            }
        }
    }

    @objc
    func emailAttendees(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            event.emailAttendees()
        }
    }

    @objc
    func openEventInFantastical(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            openInFantastical(startDate: event.startDate, title: event.title)
        }
    }
}

func shortenTitle(title: String?, offset: Int) -> String {
    var eventTitle = String(title ?? "status_bar_no_title".loco()).trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
    if eventTitle.count > offset {
        let index = eventTitle.index(eventTitle.startIndex, offsetBy: offset - 1)
        eventTitle = String(eventTitle[...index]).trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
        eventTitle += "..."
    }

    return eventTitle
}

func createEventStatusString(title: String, startDate: Date, endDate: Date) -> (String, String) {
    var eventTime: String

    var eventTitle: String
    switch Defaults[.eventTitleFormat] {
    case .show:
        if Defaults[.hideMeetingTitle] {
            eventTitle = "general_meeting".loco()
        } else {
            eventTitle = shortenTitle(title: title, offset: Defaults[.statusbarEventTitleLength])
        }
    case .dot:
        eventTitle = "•"
    case .none:
        eventTitle = ""
    }

    var isActiveEvent: Bool

    var calendar = Calendar.current
    calendar.locale = I18N.instance.locale

    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = [.minute, .hour, .day]
    formatter.calendar = calendar

    var eventDate: Date
    let prevMinute = Date().addingTimeInterval(-60)
    let now = Date()
    if startDate <= now, endDate > now {
        isActiveEvent = true
        eventDate = endDate
    } else {
        isActiveEvent = false
        eventDate = startDate
    }
    let formattedTimeLeft = formatter.string(from: prevMinute, to: eventDate)!

    if isActiveEvent {
        eventTime = "status_bar_event_status_now".loco(formattedTimeLeft)
    } else {
        eventTime = "status_bar_event_status_in".loco(formattedTimeLeft)
    }
    return (eventTitle, eventTime)
}
