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

    var eventStore: EKEventStore!
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
        eventStore = EKEventStore()

        var sources = eventStore.sources
        sources.append(contentsOf: eventStore!.delegateSources)

        eventStore = EKEventStore(sources: sources)
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
        enum NextEventState {
            case none
            case afterThreshold(EKEvent)
            case nextEvent(EKEvent)
        }

        var title = "MeetingBar"
        var time = ""
        var nextEvent: EKEvent!
        let nextEventState: NextEventState
        if !calendars.isEmpty {
            nextEvent = eventStore.getNextEvent(calendars: calendars)
            nextEventState = {
                guard let nextEvent = nextEvent else {
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
                }
                title = "🏁"
            case .nextEvent(let event):
                (title, time) = createEventStatusString(event)
                if Defaults[.joinEventNotification] {
                    scheduleEventNotification(event)
                }
            case .afterThreshold(let event):
                // Not sure, what the title should be in this case.
                title = "⏰"
                if Defaults[.joinEventNotification] {
                    scheduleEventNotification(event)
                }
            }
        } else {
            NSLog("No loaded calendars")
            nextEventState = .none
        }
        if let button = self.statusItem.button {
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
                button.image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                button.image?.size = NSSize(width: 16, height: 16)
            } else if case .afterThreshold = nextEventState {
                switch Defaults[.eventTitleIconFormat] {
                case .appicon:
                    button.image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                default:
                    button.image = NSImage(named: "iconCalendar")
                }
            }

            if button.image == nil {
                if Defaults[.eventTitleIconFormat] != EventTitleIconFormat.none {
                    let image: NSImage
                    if Defaults[.eventTitleIconFormat] == EventTitleIconFormat.eventtype {
                        image = getMeetingIcon(nextEvent)
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

    func updateMenu() {
        self.statusItemMenu.autoenablesItems = false
        self.statusItemMenu.removeAllItems()

        if !self.calendars.isEmpty {
            let today = Date()
            switch Defaults[.showEventsForPeriod] {
            case .today:
                self.createDateSection(date: today, title: "status_bar_section_today".loco())
            case .today_n_tomorrow:
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
                self.createDateSection(date: today, title: "status_bar_section_today".loco())
                self.statusItemMenu.addItem(NSMenuItem.separator())
                self.createDateSection(date: tomorrow, title: "status_bar_section_tomorrow".loco())
            }
        } else {
            let text = "status_bar_empty_calendar_message".loco()
            let item = self.statusItemMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = NSLineBreakMode.byWordWrapping
            item.attributedTitle = NSAttributedString(string: text, attributes: [NSAttributedString.Key.paragraphStyle: paragraphStyle])
            item.isEnabled = false
        }
        self.statusItemMenu.addItem(NSMenuItem.separator())
        self.createJoinSection()

        if !Defaults[.bookmarks].isEmpty {
            self.statusItemMenu.addItem(NSMenuItem.separator())

            self.createBookmarksSection()
        }
        self.statusItemMenu.addItem(NSMenuItem.separator())

        self.createPreferencesSection()
    }

    func createJoinSection() {
        if !calendars.isEmpty {
            let nextEvent = eventStore.getNextEvent(calendars: calendars)
            if nextEvent != nil {
                let joinItem = self.statusItemMenu.addItem(
                    withTitle: "status_bar_section_join_next_meeting".loco(),
                    action: #selector(AppDelegate.joinNextMeeting),
                    keyEquivalent: ""
                )
                joinItem.setShortcut(for: .joinEventShortcut)
            }
        }

        let createEventItem = NSMenuItem()
        createEventItem.title = "status_bar_section_join_create_meeting".loco()
        createEventItem.action = #selector(AppDelegate.createMeeting)
        createEventItem.keyEquivalent = ""
        createEventItem.setShortcut(for: .createMeetingShortcut)

        self.statusItemMenu.addItem(createEventItem)

        let quickActionsItem = self.statusItemMenu.addItem(
            withTitle: "status_bar_quick_actions".loco(),
            action: nil,
            keyEquivalent: ""
        )
        quickActionsItem.isEnabled = true

        quickActionsItem.submenu = NSMenu(title: "status_bar_quick_actions".loco())

        let openLinkFromClipboardItem = NSMenuItem()
        openLinkFromClipboardItem.title = "status_bar_section_join_from_clipboard".loco()
        openLinkFromClipboardItem.action = #selector(AppDelegate.openLinkFromClipboard)
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
            toggleMeetingTitleVisibilityItem.action = #selector(AppDelegate.toggleMeetingTitleVisibility)
            toggleMeetingTitleVisibilityItem.setShortcut(for: .toggleMeetingTitleVisibilityShortcut)
            quickActionsItem.submenu!.addItem(toggleMeetingTitleVisibilityItem)
        }
    }

    func createBookmarksSection() {
        let bookmarksItem = self.statusItemMenu.addItem(
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

    func createDateSection(date: Date, title: String) {
        let events: [EKEvent] = eventStore.loadEventsForDate(calendars: calendars, date: date)

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM"
        dateFormatter.locale = I18N.instance.locale

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


    func getMeetingIconForLink(_ result: MeetingLink?) -> NSImage {
            var image: NSImage? = NSImage(named: "no_online_session")
            image!.size = NSSize(width: 16, height: 16)

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
            case .some(.coscreen):
                image = NSImage(named: "coscreen_icon")!
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

            case .some(.url):
                image = NSImage(named: NSImage.touchBarOpenInBrowserTemplateName)!
                image!.size = NSSize(width: 16, height: 16)

            default:
                break
            }

            return image!
        }

    /**
     * try  to get the correct image for the specific
     */
    func getMeetingIcon(_ event: EKEvent) -> NSImage {
        let result = getMeetingLink(event)

        return getMeetingIconForLink(result)
    }

    func createEventItem(event: EKEvent, dateSection: Date) {
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
            eventTitle = shortenTitleForMenu(title: event.title)
        } else {
            eventTitle = String(event.title)
        }

        let eventTimeFormatter = DateFormatter()
        eventTimeFormatter.locale = I18N.instance.locale

        switch Defaults[.timeFormat] {
        case .am_pm:
            eventTimeFormatter.dateFormat = "hh:mm a"
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

        if !event.isAllDay && Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.show_inactive_without_meeting_link {
            let meetingLink = getMeetingLink(event)
            if meetingLink == nil {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
                shouldShowAsActive = false
            }
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
                eventMenu.addItem(withTitle: "status_bar_submenu_calendar_title".loco(event.calendar.title), action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Duration
            if !event.isAllDay {
                let eventEndTime = eventTimeFormatter.string(from: event.endDate)
                let eventDurationMinutes = String(Int(event.endDate.timeIntervalSince(event.startDate) / 60))
                let durationTitle = "status_bar_submenu_duration_all_day".loco(eventStartTime, eventEndTime, eventDurationMinutes)
                eventMenu.addItem(withTitle: durationTitle, action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Status
            if eventParticipantStatus != nil {
                var status: String
                switch eventParticipantStatus {
                case .accepted:
                    status = "status_bar_submenu_status_accepted".loco()
                case .declined:
                    status = "status_bar_submenu_status_canceled".loco()
                case .tentative:
                    status = "status_bar_submenu_status_tentative".loco()
                case .pending:
                    status = "status_bar_submenu_status_pending".loco()
                case .unknown:
                    status = "status_bar_submenu_status_unknown".loco()
                default:
                    if let eventStatus = eventParticipantStatus {
                        status = "status_bar_submenu_status_default_extended".loco(String(describing: eventStatus))
                    } else {
                        status = "status_bar_submenu_status_default_simple".loco()
                    }
                }
                eventMenu.addItem(withTitle: "status_bar_submenu_status_title".loco(status), action: nil, keyEquivalent: "")
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
                eventMenu.addItem(withTitle: "status_bar_submenu_organizer_title".loco(), action: nil, keyEquivalent: "")
                let organizerName = eventOrganizer.name ?? ""
                eventMenu.addItem(withTitle: "\(organizerName)", action: nil, keyEquivalent: "")
                eventMenu.addItem(NSMenuItem.separator())
            }

            // Notes
            if event.hasNotes {
                let notes = cleanUpNotes(event.notes ?? "")
                if !notes.isEmpty {
                    eventMenu.addItem(withTitle: "status_bar_submenu_notes_title".loco(), action: nil, keyEquivalent: "")
                    let item = eventMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.lineBreakMode = NSLineBreakMode.byWordWrapping
                    item.attributedTitle = notes.splitWithNewLineAttributedString(with: [NSAttributedString.Key.paragraphStyle: paragraphStyle], maxWidth: 300.0)
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
                eventMenu.addItem(withTitle: "status_bar_submenu_attendees_title".loco(count), action: nil, keyEquivalent: "")
                for attendee in sortedAttendees {
                    if attendee.participantType != .person {
                        continue
                    }
                    var attributes: [NSAttributedString.Key: Any] = [:]

                    var name = attendee.name ?? "status_bar_submenu_attendees_no_name".loco()

                    if attendee.isCurrentUser {
                        name = "status_bar_submenu_attendees_you".loco(name)
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

            // Open in App
            let openItem = eventMenu.addItem(withTitle: "status_bar_submenu_open_in_calendar".loco(), action: #selector(AppDelegate.openEventInCalendar), keyEquivalent: "")
            openItem.representedObject = event.eventIdentifier

            // Open in fanctastical if fantastical is installed
            if isFantasticalInstalled() {
                let fantasticalItem = eventMenu.addItem(withTitle: "status_bar_submenu_open_in_fantastical".loco(), action: #selector(AppDelegate.openEventInFantastical), keyEquivalent: "")
                fantasticalItem.representedObject = EventWithDate(event: event, dateSection: dateSection)
            }
        } else {
            eventItem.toolTip = event.title
        }
    }

    /**
     * checks if fantastical is installed
     */
    func isFantasticalInstalled () -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.flexibits.fantastical2.mac") != nil
    }


    func createPreferencesSection() {
        if removePatchVerion(Defaults[.appVersion]) > removePatchVerion(Defaults[.lastRevisedVersionInChangelog]) {
            let changelogItem = self.statusItemMenu.addItem(
                withTitle: "status_bar_whats_new".loco(),
                action: #selector(AppDelegate.openChangelogWindow),
                keyEquivalent: ""
            )
            changelogItem.image = NSImage(named: NSImage.statusAvailableName)
        }

        self.statusItemMenu.addItem(
            withTitle: "status_bar_preferences".loco(),
            action: #selector(AppDelegate.openPrefecencesWindow),
            keyEquivalent: ","
        )

        self.statusItemMenu.addItem(
            withTitle: "status_bar_quit".loco(),
            action: #selector(AppDelegate.quit),
            keyEquivalent: "q"
        )
    }
}


func shortenTitleForSystembar(title: String?) -> String {
    var eventTitle = String(title ?? "status_bar_no_title".loco()).trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
    if eventTitle.count > Defaults[.statusbarEventTitleLength] {
        let index = eventTitle.index(eventTitle.startIndex, offsetBy: Defaults[.statusbarEventTitleLength] - 1)
        eventTitle = String(eventTitle[...index]).trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
        eventTitle += "..."
    }

    return eventTitle
}

func shortenTitleForMenu(title: String?) -> String {
    var eventTitle = String(title ?? "status_bar_no_title".loco()).trimmingCharacters(in: TitleTruncationRules.excludeAtEnds)
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
        if Defaults[.hideMeetingTitle] {
            eventTitle = "general_meeting".loco()
        } else {
            eventTitle = shortenTitleForSystembar(title: event.title)
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
        eventTime = "status_bar_event_status_now".loco(formattedTimeLeft)
    } else {
        eventTime = "status_bar_event_status_in".loco(formattedTimeLeft)
    }
    return (eventTitle, eventTime)
}
