//
//  MenuBuilder.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Cocoa
import Defaults
import KeyboardShortcuts

@MainActor
struct MenuBuilder {
    /// All menu items created will forward their action to this object.
    let target: AnyObject
    let isFantasticalInstalled = checkIsFantasticalInstalled()
    var installationDate: Date?

    // MARK: Date section ------------------------------------------------------

    func buildDateSection(date: Date, title: String, events: [MBEvent]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM"
        dateFormatter.locale = I18N.instance.locale

        let dateString = dateFormatter.string(from: date)
        let dateTitle = "\(title) (\(dateString)):"
        let titleItem = NSMenuItem(
            title: dateTitle,
            action: nil,
            keyEquivalent: ""
        )
        titleItem.attributedTitle = NSAttributedString(string: dateTitle, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: MenuStyleConstants.defaultFontSize)])
        titleItem.isEnabled = false

        items.append(titleItem)

        // Events
        let sortedEvents = events.sorted {
            $0.startDate < $1.startDate
        }
        if sortedEvents.isEmpty {
            let item = NSMenuItem(
                title: "status_bar_section_date_nothing".loco(title.lowercased()),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
        }
        for event in sortedEvents {
            if let item = makeEventItem(event) {
                items.append(item)
            }
        }

        return items
    }

    // MARK: Join section ------------------------------------------------------

    func buildJoinSection(nextEvent: MBEvent?) -> [NSMenuItem] {

        var items: [NSMenuItem] = []

        // MENU ITEM: Join the meeting
        let now = Date()

        if let nextEvent = nextEvent {
            let itemTitle = nextEvent.startDate < now
                ? "status_bar_section_join_current_meeting".loco()
                : "status_bar_section_join_next_meeting".loco()

            let joinItem = NSMenuItem(
                title: itemTitle,
                action: #selector(StatusBarItemController.joinNextMeeting),
                keyEquivalent: ""
            )
            joinItem.target = target
            items.append(joinItem)
        }

        // MENU ITEM: Create meeting
        let createEventItem = NSMenuItem(
            title: "status_bar_section_join_create_meeting".loco(),
            action: #selector(StatusBarItemController.createMeetingAction),
            keyEquivalent: ""
        )
        createEventItem.target = target
        createEventItem.setShortcut(for: .createMeetingShortcut)
        items.append(createEventItem)

        // MENU ITEM: Quick actions menu
        let quickActionsItem = NSMenuItem(
            title: "status_bar_quick_actions".loco(),
            action: nil,
            keyEquivalent: ""
        )
        quickActionsItem.isEnabled = true
        quickActionsItem.submenu = NSMenu(title: "status_bar_quick_actions".loco())
        items.append(quickActionsItem)

        // MENU ITEM: QUICK ACTIONS: Dismiss meeting
        if let nextEvent = nextEvent {
            let itemTitle = nextEvent.startDate < now
                ? "status_bar_menu_dismiss_curent_meeting".loco()
                : "status_bar_menu_dismiss_next_meeting".loco()

            let dismissMeetingItem = quickActionsItem.submenu!.addItem(
                withTitle: itemTitle,
                action: #selector(StatusBarItemController.dismissNextMeetingAction),
                keyEquivalent: ""
            )
            dismissMeetingItem.target = target
        }

        if !Defaults[.dismissedEvents].isEmpty {
            let undiDismissMeetingsItem = quickActionsItem.submenu!.addItem(
                withTitle: "status_bar_menu_remove_all_dismissals".loco(),
                action: #selector(StatusBarItemController.undismissMeetingsActions),
                keyEquivalent: ""
            )
            undiDismissMeetingsItem.target = target
        }

        // MENU ITEM: QUICK ACTIONS: Open link from clipboard
        let openLinkFromClipboardItem = quickActionsItem.submenu!.addItem(
            withTitle: "status_bar_section_join_from_clipboard".loco(), action: #selector(StatusBarItemController.openLinkFromClipboardAction), keyEquivalent: ""
        )
        openLinkFromClipboardItem.target = target
        openLinkFromClipboardItem.setShortcut(for: .openClipboardShortcut)

        // MENU ITEM: QUICK ACTIONS: Toggle meeting name visibility
        if Defaults[.eventTitleFormat] == .show {
            let title = Defaults[.hideMeetingTitle]
                ? "status_bar_show_meeting_names".loco()
                : "status_bar_hide_meeting_names".loco()

            let toggleMeetingTitleVisibilityItem = quickActionsItem.submenu!.addItem(
                withTitle: title, action: #selector(StatusBarItemController.toggleMeetingTitleVisibility), keyEquivalent: ""
            )
            toggleMeetingTitleVisibilityItem.setShortcut(for: .toggleMeetingTitleVisibilityShortcut)
            toggleMeetingTitleVisibilityItem.target = target
        }

        // MENU ITEM: QUICK ACTIONS: Refresh sources
        let refrsehItem = quickActionsItem.submenu!.addItem(
            withTitle: "status_bar_section_refresh_sources".loco(),
            action: #selector(StatusBarItemController.handleManualRefresh),
            keyEquivalent: ""
        )
        refrsehItem.target = target

        return items
    }

    // MARK: Preferences section -----------------------------------------------

    func buildPreferencesSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let appMajorVersion = String(Defaults[.appVersion].dropLast(2))
        let lastRevisedMajorVersionInChangelog = String(Defaults[.lastRevisedVersionInChangelog].dropLast(2))
        let showChangelogItem = compareVersions(appMajorVersion, lastRevisedMajorVersionInChangelog)

        if showChangelogItem {
            let changelogItem = NSMenuItem(
                title: "status_bar_whats_new".loco(),
                action: #selector(AppDelegate.openChangelogWindow),
                keyEquivalent: ""
            )
            changelogItem.image = NSImage(named: NSImage.statusAvailableName)
            items.append(changelogItem)
        }

        if Defaults[.isInstalledFromAppStore] || true {
            var showRateAppButton = true

            if let installationDate = installationDate {
                let twoWeeksAfterInstallation = Calendar.current.date(byAdding: .day, value: 14, to: installationDate)!
                showRateAppButton = Date() > twoWeeksAfterInstallation
            }

            if showRateAppButton {
                let rateItem = NSMenuItem(
                    title: "status_bar_rate_app".loco(),
                    action: #selector(StatusBarItemController.rateApp),
                    keyEquivalent: ""
                )
                rateItem.target = target
                items.append(rateItem)
            }
        }

        let preferencesItem = NSMenuItem(
            title: "\("status_bar_preferences".loco())…",
            action: #selector(AppDelegate.openPreferencesWindow),
            keyEquivalent: ","
        )
        items.append(preferencesItem)

        let quitItem = NSMenuItem(
            title: "status_bar_quit".loco(),
            action: #selector(AppDelegate.quit),
            keyEquivalent: "q"
        )
        items.append(quitItem)

        return items
    }

    // MARK: Bookmarks section -------------------------------------------------

    func buildBookmarksSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let bookmarksItem = NSMenuItem(
            title: "status_bar_section_bookmarks_title".loco(),
            action: nil,
            keyEquivalent: ""
        )
        items.append(bookmarksItem)

        var bookmarksItems: [NSMenuItem] = []
        for bookmark in Defaults[.bookmarks] {
            let bookmarkItem = NSMenuItem(
                title: bookmark.name,
                action: #selector(StatusBarItemController.joinBookmark),
                keyEquivalent: ""
            )
            bookmarkItem.target = target
            bookmarkItem.representedObject = bookmark
            bookmarksItems.append(bookmarkItem)
        }

        if Defaults[.bookmarks].count > 3 {
            let bookmarksMenu = NSMenu(title: "status_bar_section_bookmarks_menu".loco())
            bookmarksItem.submenu = bookmarksMenu
            bookmarksMenu.items = bookmarksItems

        } else {
            bookmarksItem.attributedTitle = NSAttributedString(
                string: "status_bar_section_bookmarks_title".loco(),
                attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: MenuStyleConstants.defaultFontSize)]
            )
            bookmarksItem.isEnabled = false
            items.append(contentsOf: bookmarksItems)
        }

        return items
    }

    // MARK: Snapshot helper ---------------------------------------------------

    /// Titles of all items – handy for plain-text snapshot tests.
    static func plainTitles(of items: [NSMenuItem]) -> [String] {
        items.map { $0.title }
    }

    // MARK: - Private helpers --------------------------------------------------

    private func makeEventItem(_ event: MBEvent) -> NSMenuItem? {
        let eventStatus = event.status

        let now = Date()

        if event.participationStatus == .declined || eventStatus == .canceled, Defaults[.declinedEventsAppereance] == .hide {
            return nil
        }

        if event.endDate < now, Defaults[.pastEventsAppereance] == .hide {
            return nil
        }

        if event.attendees.isEmpty, Defaults[.personalEventsAppereance] == .hide {
            return nil
        }

        var eventTitle = event.title

        if Defaults[.shortenEventTitle] {
            eventTitle = shortenTitle(title: event.title, offset: Defaults[.menuEventTitleLength])
        }

        if Defaults[.dismissedEvents].contains(where: { $0.id == event.id }) {
            let dismissedMark = "status_bar_event_dismissed_mark".loco()
            eventTitle = "[\(dismissedMark)] \(eventTitle)"
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
            switch Defaults[.timeFormat] {
            case .am_pm:
                eventEndTime = "\t \t \t"
            case .military:
                eventEndTime = "\t"
            }
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

        let eventItem = NSMenuItem(
            title: itemTitle,
            action: #selector(StatusBarItemController.clickOnEvent(sender:)),
            keyEquivalent: ""
        )
        eventItem.target = target

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

        if !event.isAllDay, Defaults[.nonAllDayEvents] == .show_inactive_without_meeting_link, event.meetingLink == nil {
            styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
        }

        if event.participationStatus == .pending {
            if Defaults[.showPendingEvents] == .show_inactive {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
            } else if Defaults[.showPendingEvents] == .show_underlined {
                styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
            }
        }

        if event.participationStatus == .tentative {
            if Defaults[.showTentativeEvents] == .show_inactive {
                styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
            } else if Defaults[.showTentativeEvents] == .show_underlined {
                styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
            }
        }

        if event.attendees.isEmpty, Defaults[.personalEventsAppereance] == .show_inactive {
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
                eventItem.image = eventItem.image?.tintedDisabled()
            }
        } else if event.startDate < now, event.endDate > now, eventStatus != .canceled {
            eventItem.state = .mixed

            // if highlightRunningEvent
            eventItem.mixedStateImage = nil

            // create an NSMutableAttributedString that we'll append everything to
            let eventTitle = NSMutableAttributedString()

            if shouldShowAsActive, Defaults[.showPendingEvents] != .show_underlined {
                // add the NSTextAttachment wrapper to our full string, then add some more text.
                styles[NSAttributedString.Key.font] = NSFont.boldSystemFont(ofSize: 14)
            } else {
                styles[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: 14)
            }

            if shouldShowAsActive, Defaults[.showTentativeEvents] != .show_underlined {
                // add the NSTextAttachment wrapper to our full string, then add some more text.
                styles[NSAttributedString.Key.font] = NSFont.boldSystemFont(ofSize: 14)
            } else {
                styles[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: 14)
            }

            eventTitle.append(NSAttributedString(string: itemTitle, attributes: styles))

            if shouldShowAsActive {
                // create our NSTextAttachment
                let runningImage = NSTextAttachment()
                runningImage.image = NSImage(named: MenuStyleConstants.runningIconName)
                runningImage.image?.size = MenuStyleConstants.iconSize

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
            let copyLinkItem = eventMenu.addItem(withTitle: "status_bar_submenu_copy_meeting_link".loco(), action: #selector(StatusBarItemController.copyEventMeetingLink), keyEquivalent: "")
            copyLinkItem.target = target
            copyLinkItem.representedObject = event

            // Dismiss/undismiss meeting
            if Defaults[.dismissedEvents].contains(where: { $0.id == event.id }) {
                let undismissItem = eventMenu.addItem(withTitle: "status_bar_submenu_undismiss_meeting".loco(), action: #selector(StatusBarItemController.undismissEvent), keyEquivalent: "")
                undismissItem.target = target
                undismissItem.representedObject = event
            } else {
                let dismissItem = eventMenu.addItem(withTitle: "status_bar_submenu_dismiss_meeting".loco(), action: #selector(StatusBarItemController.dismissEvent), keyEquivalent: "")
                dismissItem.target = target
                dismissItem.representedObject = event
            }

            // Send email
            let emailItem = eventMenu.addItem(withTitle: "status_bar_submenu_email_attendees".loco(), action: #selector(StatusBarItemController.emailAttendees), keyEquivalent: "")
            emailItem.target = target
            emailItem.representedObject = event

            // Open in App
            let openItem = eventMenu.addItem(withTitle: "status_bar_submenu_open_in_calendar".loco(), action: #selector(StatusBarItemController.openEventInCalendar), keyEquivalent: "")
            openItem.target = target
            openItem.representedObject = event.id

            // Open in fanctastical if fantastical is installed
            if isFantasticalInstalled {
                let fantasticalItem = eventMenu.addItem(withTitle: "status_bar_submenu_open_in_fantastical".loco(), action: #selector(StatusBarItemController.openEventInFantastical), keyEquivalent: "")
                fantasticalItem.target = target
                fantasticalItem.representedObject = event
            }
        } else {
            eventItem.toolTip = event.title
        }
        return eventItem
    }
}
