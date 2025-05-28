//
//  StatusBarItemController.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import Combine

import Defaults
import KeyboardShortcuts
import SwiftUI

enum MenuStyleConstants {
    static let defaultFontSize: CGFloat = 13
    static let runningIconName = "running_icon"
    static let appIconName = "AppIcon"
    static let calendarCheckmarkIconName = "iconCalendarCheckmark"
    static let calendarIconName = "iconCalendar"
    static let iconSize: NSSize = .init(width: 16, height: 16)
}

/**
 * creates the menu in the system status bar, creates the menu items and controls the whole lifecycle.
 */
@MainActor
final class StatusBarItemController {
    var statusItem: NSStatusItem!
    var statusItemMenu: NSMenu!

    var events: [MBEvent] = []

    let installationDate = getInstallationDate()

    weak var appdelegate: AppDelegate!

    private var cancellables = Set<AnyCancellable>()

    init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItemMenu = NSMenu(title: "MeetingBar in Status Bar Menu")

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusMenuBarAction)
        statusItem.button?.sendAction(on: [NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseUp, NSEvent.EventTypeMask.leftMouseDown])

        // Temporary icon and menu before app delegate setup
        statusItem.button?.image = NSImage(named: MenuStyleConstants.appIconName)!
        statusItem.button?.image?.size = MenuStyleConstants.iconSize
        statusItem.button?.imagePosition = .imageLeft
        let menuItem = statusItemMenu.addItem(withTitle: "window_title_onboarding".loco(), action: nil, keyEquivalent: "")
        menuItem.isEnabled = false

        setupDefaultsObservers()
        setupKeyboardShortcuts()
    }

    private func setupDefaultsObservers() {
        // For all these keys, just redraw:
        Defaults.publisher(
            keys: .statusbarEventTitleLength, .eventTimeFormat,
            .eventTitleIconFormat, .showEventMaxTimeUntilEventThreshold,
            .showEventMaxTimeUntilEventEnabled, .showEventDetails,
            .shortenEventTitle, .menuEventTitleLength,
            .showEventEndTime, .showMeetingServiceIcon,
            .timeFormat, .bookmarks, .eventTitleFormat,
            .personalEventsAppereance, .pastEventsAppereance,
            .declinedEventsAppereance, .ongoingEventVisibility,
            .showTimelineInMenu,
            options: []
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateTitle()
            self?.updateMenu()
        }
        .store(in: &cancellables)

        Defaults.publisher(.hideMeetingTitle, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenu()
                self?.updateTitle()

                // Reschedule next notification with updated event name visibility
                removePendingNotificationRequests(withID: notificationIDs.event_starts)
                removePendingNotificationRequests(withID: notificationIDs.event_ends)
                if let nextEvent = self?.events.nextEvent() {
                    Task {
                        await scheduleEventNotification(nextEvent)
                    }
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.preferredLanguage, options: [.initial])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if I18N.instance.changeLanguage(to: change.newValue) {
                    self?.updateMenu()
                    self?.updateTitle()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.joinEventNotification, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if change.newValue == true {
                    if let nextEvent = self?.events.nextEvent() {
                        Task {
                            await scheduleEventNotification(nextEvent)
                        }
                    }
                } else {
                    removePendingNotificationRequests(withID: notificationIDs.event_starts)
                }
            }
            .store(in: &cancellables)
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut, action: createMeeting)

        KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
            Task { @MainActor in self.joinNextMeeting() }
        }

        KeyboardShortcuts.onKeyUp(for: .openMenuShortcut) {
            Task { @MainActor in self.openMenu() }
        }

        KeyboardShortcuts.onKeyUp(for: .openClipboardShortcut, action: openLinkFromClipboard)

        KeyboardShortcuts.onKeyUp(for: .toggleMeetingTitleVisibilityShortcut) {
            Defaults[.hideMeetingTitle].toggle()
        }
    }

    @objc
    func statusMenuBarAction(sender _: NSStatusItem) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            // Right button click
            joinNextMeeting()
        } else if event == nil || event?.type == .leftMouseDown || event?.type == .leftMouseUp {
            // show the menu as normal
            openMenu()
        }
    }

    func openMenu() {
        statusItem.menu = statusItemMenu
        statusItem.button?.performClick(nil) // ...and click
        statusItem.menu = nil
    }

    func setAppDelegate(appdelegate: AppDelegate) {
        self.appdelegate = appdelegate
    }

    func updateTitle() {
        var title = "MeetingBar"
        var time = ""
        var nextEvent: MBEvent!
        let nextEventState: NextEventState
        if Defaults[.selectedCalendarIDs].isEmpty == false {
            nextEvent = events.nextEvent()
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
                    removePendingNotificationRequests(withID: notificationIDs.event_starts)
                    removeDeliveredNotifications()
                }
                title = "🏁"
            case let .nextEvent(event):
                (title, time) = createEventStatusString(title: event.title, startDate: event.startDate, endDate: event.endDate)
                if Defaults[.joinEventNotification] {
                    Task {
                        await scheduleEventNotification(event)
                    }
                }
            case let .afterThreshold(event):
                // Not sure, what the title should be in this case.
                title = "⏰"
                if Defaults[.joinEventNotification] {
                    Task {
                        await scheduleEventNotification(event)
                    }
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
                    button.image = NSImage(named: MenuStyleConstants.calendarCheckmarkIconName)
                }
                button.image?.size = MenuStyleConstants.iconSize
            } else if title == "MeetingBar" {
                button.image = NSImage(named: MenuStyleConstants.appIconName)!
                button.image?.size = MenuStyleConstants.iconSize
            } else if case .afterThreshold = nextEventState {
                switch Defaults[.eventTitleIconFormat] {
                case .appicon:
                    button.image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                default:
                    button.image = NSImage(named: MenuStyleConstants.calendarIconName)
                }
            }

            if button.image == nil {
                if Defaults[.eventTitleIconFormat] != .none {
                    let image: NSImage
                    if Defaults[.eventTitleIconFormat] == .eventtype {
                        image = getIconForMeetingService(nextEvent.meetingLink?.service)
                    } else {
                        image = NSImage(named: Defaults[.eventTitleIconFormat].rawValue)!
                    }

                    button.image = image
                    button.image?.size = MenuStyleConstants.iconSize
                }

                if button.image?.name() == "no_online_session" {
                    button.imagePosition = .noImage
                } else {
                    button.imagePosition = .imageLeft
                }

                // create an NSMutableAttributedString that we'll append everything to
                let menuTitle = NSMutableAttributedString()

                if Defaults[.eventTimeFormat] != .show_under_title || Defaults[.eventTitleFormat] == .none {
                    var eventTitle = title
                    if Defaults[.eventTimeFormat] == .show {
                        eventTitle += " " + time
                    }

                    var styles = [NSAttributedString.Key: Any]()
                    styles[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize)

                    if nextEvent.participationStatus == .pending, Defaults[.showPendingEvents] == .show_underlined {
                        styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
                    }

                    if nextEvent.participationStatus == .tentative, Defaults[.showTentativeEvents] == .show_underlined {
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

                    if nextEvent.participationStatus == .pending, Defaults[.showPendingEvents] == .show_inactive {
                        styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
                    } else if nextEvent.participationStatus == .pending, Defaults[.showPendingEvents] == .show_underlined {
                        styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
                    }

                    if nextEvent.participationStatus == .tentative, Defaults[.showTentativeEvents] == .show_inactive {
                        styles[NSAttributedString.Key.foregroundColor] = NSColor.disabledControlTextColor
                    } else if nextEvent.participationStatus == .tentative, Defaults[.showTentativeEvents] == .show_underlined {
                        styles[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.byWord.rawValue
                    }

                    menuTitle.append(NSAttributedString(string: title, attributes: styles))

                    let timeAttributes = [
                        NSAttributedString.Key.font: NSFont.systemFont(ofSize: 9),
                        NSAttributedString.Key.foregroundColor: NSColor.lightGray
                    ]
                    menuTitle.append(NSAttributedString(string: "\n" + time, attributes: timeAttributes))

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
        // Don't update the menu while it's open to avoid flickering
        if statusItem.menu != nil {
            return
        }

        let builder = MenuBuilder(target: self, installationDate: installationDate)

        statusItemMenu.autoenablesItems = false
        statusItemMenu.removeAllItems()

        if Defaults[.selectedCalendarIDs].isEmpty == false {
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

            // VIEW
            if Defaults[.showTimelineInMenu], events.isEmpty == false {
                let segments = events.map {
                    DaySegment(start: max($0.startDate, today),
                               end: min($0.endDate, tomorrow),
                               color: Color($0.calendar.color))
                }

                let timeline = DayRelativeTimelineView(segments: segments, currentDate: Date())
                let hosting  = NSHostingView(rootView: timeline)
                hosting.autoresizingMask = [.width]
                hosting.frame.size.height = timeline.preferredHeight

                let item = NSMenuItem()
                item.view = hosting
                statusItemMenu.addItem(item)
                statusItemMenu.addItem(.separator())
            }
            //

            switch Defaults[.showEventsForPeriod] {
            case .today:
                statusItemMenu.items += builder.buildDateSection(date: today, title: "status_bar_section_today".loco(), events: events)
            case .today_n_tomorrow:
                let todayEvents = events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: today) }
                statusItemMenu.items += builder.buildDateSection(date: today, title: "status_bar_section_today".loco(), events: todayEvents)

                statusItemMenu.addItem(NSMenuItem.separator())

                let tomorrowEvents = events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: tomorrow) }
                statusItemMenu.items += builder.buildDateSection(date: tomorrow, title: "status_bar_section_tomorrow".loco(), events: tomorrowEvents)

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
        statusItemMenu.items += builder.buildJoinSection(nextEvent: events.nextEvent())

        if !Defaults[.bookmarks].isEmpty {
            statusItemMenu.addItem(NSMenuItem.separator())

            statusItemMenu.items += builder.buildBookmarksSection()
        }
        statusItemMenu.addItem(NSMenuItem.separator())

        statusItemMenu.items += builder.buildPreferencesSection()
    }

    /*
     * -----------------------
     * MARK: - Actions
     * ------------------------
     */

    @objc func createMeetingAction() {
        createMeeting()
    }

    @objc
    func joinNextMeeting() {
        if let nextEvent = events.nextEvent() {
            nextEvent.openMeeting()
        } else {
            sendNotification("next_meeting_empty_title".loco(), "next_meeting_empty_message".loco())
        }
    }

    @objc
    func dismissNextMeetingAction() {
        if let nextEvent = events.nextEvent() {
            let dismissedEvent = ProcessedEvent(id: nextEvent.id, lastModifiedDate: nextEvent.lastModifiedDate, eventEndDate: nextEvent.endDate)
            Defaults[.dismissedEvents].append(dismissedEvent)
            sendNotification("notification_next_meeting_dismissed_title".loco(nextEvent.title), "notification_next_meeting_dismissed_message".loco())

            updateTitle()
            updateMenu()
        }
    }

    @objc
    func undismissMeetingsActions() {
        Defaults[.dismissedEvents] = []
        sendNotification("notification_all_dismissals_removed_title".loco(), "notification_all_dismissals_removed_message".loco())

        updateTitle()
        updateMenu()
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
    func rateApp() {
        Links.rateAppInAppStore.openInDefaultBrowser()
    }

    @objc
    func joinBookmark(sender: NSMenuItem) {
        if let bookmark: Bookmark = sender.representedObject as? Bookmark {
            openMeetingURL(bookmark.service, bookmark.url, nil)
        }
    }

    @objc
    func clickOnEvent(sender: NSMenuItem) {
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

    @objc func handleManualRefresh() {
        Task {
            do { try await self.appdelegate.eventManager.refreshSources() } catch { NSLog("Refresh failed: \(error)") }
        }
    }

    @objc
    func dismissEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            dismiss(event: event)
        }
    }

    func dismiss(event: MBEvent) {
        let dismissedEvent = ProcessedEvent(id: event.id, lastModifiedDate: event.lastModifiedDate, eventEndDate: event.endDate)
        Defaults[.dismissedEvents].append(dismissedEvent)

        updateTitle()
        updateMenu()
    }

    @objc
    func undismissEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            Defaults[.dismissedEvents] = Defaults[.dismissedEvents].filter { $0.id != event.id }

            updateTitle()
            updateMenu()
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
            eventTitle = shortenTitle(title: title, offset: Defaults[.statusbarEventTitleLength]).replacingOccurrences(of: "\n", with: " ")
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

enum NextEventState {
    case none
    case afterThreshold(MBEvent)
    case nextEvent(MBEvent)
}
