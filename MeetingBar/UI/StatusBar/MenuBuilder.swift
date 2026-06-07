//
//  MenuBuilder.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Cocoa
import KeyboardShortcuts

@MainActor
struct MenuBuilder {
    /// All menu items created will forward their action to this object.
    let target: AnyObject
    /// Snapshot of all events, settings, and pre-computed flags used while
    /// building this menu. Replaces direct `Defaults` reads.
    /// Defaults to a zero-state snapshot for tests that don't exercise
    /// state-driven branches; production callers must pass a real snapshot.
    var state: StatusBarMenuState = StatusBarMenuState()
    var isFantasticalInstalled = checkIsFantasticalInstalled()
    var installationDate: Date?
    var now: Date = Date()

    // MARK: Meeting control section ------------------------------------------

    func buildMeetingControlSection() -> [NSMenuItem] {
        if let event = state.nextEvent {
            return buildMeetingControlSection(event: event)
        }
        // emptyStateReason does not propagate .stale, so when the provider is
        // stale and the only reason for an empty section is that there are no
        // upcoming meetings, replace the generic message with the stale warning.
        if state.providerWarning == .stale,
           state.emptyStateReason == .noUpcomingMeetings || state.emptyStateReason == nil {
            return buildProviderWarningItems()
        }
        return buildEmptyMeetingControlSection()
    }

    private func buildMeetingControlSection(event: MBEvent) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let isCurrent = event.startDate <= now && event.endDate > now
        items.append(statusItem(
            title: isCurrent
                ? "status_bar_control_current_meeting".loco()
                : "status_bar_control_next_meeting".loco()
        ))

        let displayTitle = state.statusBar.hideMeetingTitle
            ? "general_meeting".loco()
            : event.title
        let title = displayTitle.isEmpty ? "status_bar_no_title".loco() : displayTitle
        let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: MenuStyleConstants.defaultFontSize + 1)
            ]
        )
        titleItem.isEnabled = false
        titleItem.image = getIconForMeetingService(event.meetingLink?.service)
        items.append(titleItem)

        let time = eventTimePresentation(for: event)
        let timeRange = event.isAllDay
            ? time.start
            : "\(time.start) – \(time.end)"
        let context = [timeRange, event.calendar.title, event.calendar.source]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        let contextItem = NSMenuItem(title: context, action: nil, keyEquivalent: "")
        contextItem.isEnabled = false
        items.append(contextItem)

        if event.meetingLink != nil {
            let joinTitle = event.startDate < now
                ? "status_bar_control_join_current".loco()
                : "status_bar_control_join_next".loco()
            let joinItem = NSMenuItem(
                title: joinTitle,
                action: #selector(StatusBarItemController.joinEvent),
                keyEquivalent: ""
            )
            joinItem.target = target
            joinItem.representedObject = event
            joinItem.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)
            items.append(joinItem)
        } else {
            let noLinkItem = NSMenuItem(
                title: "status_bar_control_no_meeting_link".loco(),
                action: nil,
                keyEquivalent: ""
            )
            noLinkItem.isEnabled = false
            items.append(noLinkItem)
        }

        items.append(makeMeetingActionsItem(for: event))
        items.append(contentsOf: buildProviderWarningItems())
        return items
    }

    private func buildProviderWarningItems() -> [NSMenuItem] {
        guard let warning = state.providerWarning else { return [] }

        let title: String
        let actionTitle: String
        let action: Selector

        switch warning {
        case .authRequired:
            title = "status_bar_control_auth_required".loco()
            actionTitle = "status_bar_control_reconnect".loco()
            action = #selector(StatusBarItemController.reconnectProviderAction)
        case .permissionRequired:
            title = "status_bar_control_permission_required".loco()
            actionTitle = "status_bar_control_grant_permission".loco()
            action = #selector(StatusBarItemController.openCalendarPermissionsAction)
        case .stale:
            title = "status_bar_control_stale".loco()
            actionTitle = "status_bar_section_refresh_sources".loco()
            action = #selector(StatusBarItemController.handleManualRefresh)
        case .refreshFailed:
            title = "status_bar_control_refresh_failed".loco()
            actionTitle = "status_bar_section_refresh_sources".loco()
            action = #selector(StatusBarItemController.handleManualRefresh)
        }

        let actionItem = NSMenuItem(title: actionTitle, action: action, keyEquivalent: "")
        actionItem.target = target
        return [statusItem(title: title), actionItem]
    }

    private func makeMeetingActionsItem(for event: MBEvent) -> NSMenuItem {
        let title = "status_bar_control_actions".loco()
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        addEventActions(to: menu, event: event)
        item.submenu = menu
        return item
    }

    private func buildEmptyMeetingControlSection() -> [NSMenuItem] {
        let reason = state.emptyStateReason ?? .noUpcomingMeetings
        let title: String
        let actionTitle: String
        let action: Selector

        switch reason {
        case .authRequired:
            title = "status_bar_control_auth_required".loco()
            actionTitle = "status_bar_control_reconnect".loco()
            action = #selector(StatusBarItemController.reconnectProviderAction)
        case .permissionRequired:
            title = "status_bar_control_permission_required".loco()
            actionTitle = "status_bar_control_grant_permission".loco()
            action = #selector(StatusBarItemController.openCalendarPermissionsAction)
        case .noCalendarsSelected:
            title = "status_bar_control_no_calendars".loco()
            actionTitle = "status_bar_control_select_calendars".loco()
            action = #selector(StatusBarItemController.openPreferencesAction)
        case .refreshFailed:
            title = "status_bar_control_refresh_failed".loco()
            actionTitle = "status_bar_section_refresh_sources".loco()
            action = #selector(StatusBarItemController.handleManualRefresh)
        case .noUpcomingMeetings:
            title = "status_bar_control_no_upcoming".loco()
            actionTitle = "status_bar_section_refresh_sources".loco()
            action = #selector(StatusBarItemController.handleManualRefresh)
        }

        let titleItem = statusItem(title: title, bold: true)
        let actionItem = NSMenuItem(title: actionTitle, action: action, keyEquivalent: "")
        actionItem.target = target
        return [titleItem, actionItem]
    }

    private func statusItem(title: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if bold {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.boldSystemFont(ofSize: MenuStyleConstants.defaultFontSize)]
            )
        }
        item.isEnabled = false
        return item
    }

    // MARK: Date section ------------------------------------------------------

    func buildDateSection(
        date: Date,
        title: String,
        events: [MBEvent],
        subdueEmptyState: Bool = false
    ) -> [NSMenuItem] {
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
        titleItem.attributedTitle = NSAttributedString(
            string: dateTitle,
            attributes: [
                NSAttributedString.Key.font: NSFont.boldSystemFont(
                    ofSize: MenuStyleConstants.defaultFontSize)
            ])
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
            if subdueEmptyState {
                item.attributedTitle = NSAttributedString(
                    string: item.title,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize - 1),
                        .foregroundColor: NSColor.disabledControlTextColor
                    ]
                )
            }
            items.append(item)
        }
        for event in sortedEvents {
            if let item = makeEventItem(event) {
                items.append(item)
            }
        }

        return items
    }

    // MARK: Join section ------------------------------------------------------

    func buildJoinSection(
        nextEvent: MBEvent?,
        includeJoinAction: Bool = true
    ) -> [NSMenuItem] {

        var items: [NSMenuItem] = []

        // MENU ITEM: Join the meeting
        let now = self.now

        if let nextEvent = nextEvent, includeJoinAction {
            let itemTitle =
                nextEvent.startDate < now
                ? "status_bar_section_join_current_meeting".loco()
                : "status_bar_section_join_next_meeting".loco()

            let joinItem = NSMenuItem(
                title: itemTitle,
                action: #selector(StatusBarItemController.joinNextMeeting),
                keyEquivalent: ""
            )
            joinItem.target = target
            items.append(joinItem)

            if let alternateLinksItem = makeAlternateMeetingLinksMenu(for: nextEvent) {
                items.append(alternateLinksItem)
            }
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
        let quickActionsSubmenu = NSMenu(title: "status_bar_quick_actions".loco())
        quickActionsItem.submenu = quickActionsSubmenu
        items.append(quickActionsItem)

        // MENU ITEM: QUICK ACTIONS: Dismiss meeting
        if let nextEvent = nextEvent {
            let itemTitle =
                nextEvent.startDate < now
                ? "status_bar_menu_dismiss_curent_meeting".loco()
                : "status_bar_menu_dismiss_next_meeting".loco()

            let dismissMeetingItem = quickActionsSubmenu.addItem(
                withTitle: itemTitle,
                action: #selector(StatusBarItemController.dismissNextMeetingAction),
                keyEquivalent: ""
            )
            dismissMeetingItem.target = target
        }

        if !state.events.dismissedEvents.isEmpty {
            let undiDismissMeetingsItem = quickActionsSubmenu.addItem(
                withTitle: "status_bar_menu_remove_all_dismissals".loco(),
                action: #selector(StatusBarItemController.undismissMeetingsActions),
                keyEquivalent: ""
            )
            undiDismissMeetingsItem.target = target
        }

        // MENU ITEM: QUICK ACTIONS: Open link from clipboard
        let openLinkFromClipboardItem = quickActionsSubmenu.addItem(
            withTitle: "status_bar_section_join_from_clipboard".loco(),
            action: #selector(StatusBarItemController.openLinkFromClipboardAction),
            keyEquivalent: ""
        )
        openLinkFromClipboardItem.target = target
        openLinkFromClipboardItem.setShortcut(for: .openClipboardShortcut)

        // MENU ITEM: QUICK ACTIONS: Toggle meeting name visibility
        if state.statusBar.eventTitleFormat == .show {
            let title =
                state.statusBar.hideMeetingTitle
                ? "status_bar_show_meeting_names".loco()
                : "status_bar_hide_meeting_names".loco()

            let toggleMeetingTitleVisibilityItem = quickActionsSubmenu.addItem(
                withTitle: title,
                action: #selector(StatusBarItemController.toggleMeetingTitleVisibility),
                keyEquivalent: ""
            )
            toggleMeetingTitleVisibilityItem.setShortcut(for: .toggleMeetingTitleVisibilityShortcut)
            toggleMeetingTitleVisibilityItem.target = target
        }

        // MENU ITEM: QUICK ACTIONS: Refresh sources
        let refrsehItem = quickActionsSubmenu.addItem(
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

        let showChangelogItem = compareVersions(
            state.appMajorVersion, state.lastRevisedMajorVersion)

        if showChangelogItem {
            let changelogItem = NSMenuItem(
                title: "status_bar_whats_new".loco(),
                action: #selector(StatusBarItemController.openChangelogAction),
                keyEquivalent: ""
            )
            changelogItem.image = NSImage(named: NSImage.statusAvailableName)
            changelogItem.target = target
            items.append(changelogItem)
        }

        var showRateAppButton = true
        if let installationDate {
            let twoWeeksAfterInstallation = Calendar.current.date(
                byAdding: .day,
                value: 14,
                to: installationDate
            )!
            showRateAppButton = now > twoWeeksAfterInstallation
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

        let preferencesItem = NSMenuItem(
            title: "\("status_bar_preferences".loco())…",
            action: #selector(StatusBarItemController.openPreferencesAction),
            keyEquivalent: ","
        )
        preferencesItem.target = target
        items.append(preferencesItem)

        let quitItem = NSMenuItem(
            title: "status_bar_quit".loco(),
            action: #selector(StatusBarItemController.quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = target
        items.append(quitItem)

        return items
    }

    // MARK: Bookmarks section -------------------------------------------------

    func buildBookmarksSection(bookmarks: [Bookmark]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let bookmarksItem = NSMenuItem(
            title: "status_bar_section_bookmarks_title".loco(),
            action: nil,
            keyEquivalent: ""
        )
        items.append(bookmarksItem)

        var bookmarksItems: [NSMenuItem] = []
        for bookmark in bookmarks {
            let bookmarkItem = NSMenuItem(
                title: bookmark.name,
                action: #selector(StatusBarItemController.joinBookmark),
                keyEquivalent: ""
            )
            bookmarkItem.target = target
            bookmarkItem.representedObject = bookmark
            bookmarksItems.append(bookmarkItem)
        }

        if bookmarks.count > 3 {
            let bookmarksMenu = NSMenu(title: "status_bar_section_bookmarks_menu".loco())
            bookmarksItem.submenu = bookmarksMenu
            bookmarksMenu.items = bookmarksItems

        } else {
            bookmarksItem.attributedTitle = NSAttributedString(
                string: "status_bar_section_bookmarks_title".loco(),
                attributes: [
                    NSAttributedString.Key.font: NSFont.boldSystemFont(
                        ofSize: MenuStyleConstants.defaultFontSize)
                ]
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
        guard shouldRenderEvent(event) else { return nil }

        let menuTitle = eventMenuTitle(for: event)
        let time = eventTimePresentation(for: event)
        let itemTitle = eventItemTitle(
            eventTitle: menuTitle,
            startTime: time.start,
            endTime: time.end
        )
        let eventItem = makeBaseEventItem(event: event, title: itemTitle)

        applyEventItemAppearance(eventItem, event: event, title: itemTitle)
        eventItem.representedObject = event
        configureEventDetails(
            for: eventItem,
            event: event,
            menuTitle: menuTitle,
            time: time
        )

        return eventItem
    }

    private struct EventTimePresentation {
        let formatter: DateFormatter
        let start: String
        let end: String
    }

    private struct EventItemStyle {
        var attributes: [NSAttributedString.Key: Any] = [:]
        var shouldShowAsActive = true
    }

    private func shouldRenderEvent(_ event: MBEvent) -> Bool {
        if event.participationStatus == .declined || event.status == .canceled,
            state.events.declinedEventsAppearance == .hide {
            return false
        }
        if event.endDate < now, state.events.pastEventsAppearance == .hide {
            return false
        }
        if event.attendees.isEmpty, state.events.personalEventsAppearance == .hide {
            return false
        }
        return true
    }

    private func eventMenuTitle(for event: MBEvent) -> String {
        var title = event.title
        if state.menu.shortenEventTitle {
            title = StatusBarTitlePolicy.shortenTitle(
                event.title,
                limit: state.menu.menuEventTitleLength,
                noTitle: "status_bar_no_title".loco()
            )
        }
        if isDismissed(event) {
            title = "[\("status_bar_event_dismissed_mark".loco())] \(title)"
        }
        return title
    }

    private func eventTimePresentation(for event: MBEvent) -> EventTimePresentation {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale

        switch state.timeFormat {
        case .am_pm:
            formatter.dateFormat = "h:mm a  "
        case .military:
            formatter.dateFormat = "HH:mm"
        }

        guard event.isAllDay else {
            return EventTimePresentation(
                formatter: formatter,
                start: formatter.string(from: event.startDate),
                end: formatter.string(from: event.endDate)
            )
        }

        let end = state.timeFormat == .am_pm ? "\t \t \t" : "\t"
        return EventTimePresentation(
            formatter: formatter,
            start: "status_bar_event_start_time_all_day".loco(),
            end: end
        )
    }

    private func eventItemTitle(
        eventTitle: String,
        startTime: String,
        endTime: String
    ) -> String {
        if state.statusBar.showEventEndTime {
            return "\(startTime) \t \(endTime) \t \(eventTitle)"
        }
        return "\(startTime) \t \(eventTitle)"
    }

    private func makeBaseEventItem(event: MBEvent, title: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(StatusBarItemController.clickOnEvent(sender:)),
            keyEquivalent: ""
        )
        item.target = target
        if state.menu.showMeetingServiceIcon {
            item.image = getIconForMeetingService(event.meetingLink?.service)
        }
        return item
    }

    private func applyEventItemAppearance(
        _ item: NSMenuItem,
        event: MBEvent,
        title: String
    ) {
        var style = baseEventItemStyle(for: event)

        if event.endDate < now, event.status != .canceled {
            applyPastEventAppearance(item, title: title, style: &style)
        } else if event.startDate < now, event.endDate > now, event.status != .canceled {
            applyRunningEventAppearance(item, title: title, style: style)
        } else {
            applyUpcomingEventAppearance(item, title: title, style: style)
        }
    }

    private func baseEventItemStyle(for event: MBEvent) -> EventItemStyle {
        var style = EventItemStyle()

        if event.participationStatus == .declined || event.status == .canceled {
            if state.events.declinedEventsAppearance == .show_inactive {
                style.attributes[.foregroundColor] = NSColor.disabledControlTextColor
            } else {
                style.attributes[.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
            }
            style.shouldShowAsActive = false
        }

        if !event.isAllDay,
            state.events.nonAllDayEvents == .show_inactive_without_meeting_link,
            event.meetingLink == nil {
            style.attributes[.foregroundColor] = NSColor.disabledControlTextColor
        }

        applyParticipationStyle(
            statusMatches: event.participationStatus == .pending,
            showInactive: state.events.showPendingEvents == .show_inactive,
            showUnderlined: state.events.showPendingEvents == .show_underlined,
            to: &style.attributes
        )
        applyParticipationStyle(
            statusMatches: event.participationStatus == .tentative,
            showInactive: state.events.showTentativeEvents == .show_inactive,
            showUnderlined: state.events.showTentativeEvents == .show_underlined,
            to: &style.attributes
        )

        if event.attendees.isEmpty, state.events.personalEventsAppearance == .show_inactive {
            style.attributes[.foregroundColor] = NSColor.disabledControlTextColor
            style.shouldShowAsActive = false
        }

        return style
    }

    private func applyParticipationStyle(
        statusMatches: Bool,
        showInactive: Bool,
        showUnderlined: Bool,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        guard statusMatches else { return }

        if showInactive {
            attributes[.foregroundColor] = NSColor.disabledControlTextColor
        } else if showUnderlined {
            attributes[.underlineStyle] =
                NSUnderlineStyle.single.rawValue
                | NSUnderlineStyle.patternDot.rawValue
                | NSUnderlineStyle.byWord.rawValue
        }
    }

    private func applyPastEventAppearance(
        _ item: NSMenuItem,
        title: String,
        style: inout EventItemStyle
    ) {
        item.state = .on
        item.onStateImage = nil

        guard state.events.pastEventsAppearance == .show_inactive else { return }
        style.attributes[.foregroundColor] = NSColor.disabledControlTextColor
        style.attributes[.font] = NSFont.systemFont(ofSize: 14)
        item.attributedTitle = NSAttributedString(string: title, attributes: style.attributes)
        item.image = item.image?.tintedDisabled()
    }

    private func applyRunningEventAppearance(
        _ item: NSMenuItem,
        title: String,
        style: EventItemStyle
    ) {
        item.state = .mixed
        item.mixedStateImage = nil

        var attributes = style.attributes
        attributes[.font] = runningEventFont(shouldShowAsActive: style.shouldShowAsActive)

        let attributedTitle = NSMutableAttributedString(
            string: title,
            attributes: attributes
        )
        if style.shouldShowAsActive {
            let runningImage = NSTextAttachment()
            runningImage.image = NSImage(named: MenuStyleConstants.runningIconName)
            runningImage.image?.size = MenuStyleConstants.iconSize
            attributedTitle.append(NSAttributedString(string: " "))
            attributedTitle.append(NSAttributedString(attachment: runningImage))
        }
        item.attributedTitle = attributedTitle
    }

    private func runningEventFont(shouldShowAsActive: Bool) -> NSFont {
        if shouldShowAsActive, state.events.showTentativeEvents != .show_underlined {
            return NSFont.boldSystemFont(ofSize: 14)
        }
        return NSFont.systemFont(ofSize: 14)
    }

    private func applyUpcomingEventAppearance(
        _ item: NSMenuItem,
        title: String,
        style: EventItemStyle
    ) {
        item.state = .off
        item.offStateImage = nil
        item.attributedTitle = NSAttributedString(string: title, attributes: style.attributes)
    }

    private func configureEventDetails(
        for item: NSMenuItem,
        event: MBEvent,
        menuTitle: String,
        time: EventTimePresentation
    ) {
        guard state.menu.showEventDetails else {
            item.toolTip = event.title
            return
        }

        let menu = NSMenu(title: "Item \(menuTitle) menu")
        item.submenu = menu

        addEventTitle(to: menu, event: event)
        addEventStatus(to: menu, event: event)
        addEventDuration(to: menu, event: event, time: time)
        addEventCalendar(to: menu, event: event)
        addEventLocation(to: menu, event: event)
        addEventOrganizer(to: menu, event: event)
        addEventNotes(to: menu, event: event)
        addEventAttendees(to: menu, event: event)
        addEventActions(to: menu, event: event)
    }

    private func addEventTitle(to menu: NSMenu, event: MBEvent) {
        let titleItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        titleItem.view = createNSViewFromText(
            text: event.title,
            font: NSFont.boldSystemFont(ofSize: 15),
            maxWidth: 420
        )
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventStatus(to menu: NSMenu, event: MBEvent) {
        let status: String
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
            status = "status_bar_submenu_status_default_extended".loco(
                String(describing: event.status)
            )
        }
        menu.addItem(
            withTitle: "status_bar_submenu_status_title".loco(status),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventDuration(
        to menu: NSMenu,
        event: MBEvent,
        time: EventTimePresentation
    ) {
        guard !event.isAllDay else { return }

        let durationMinutes = String(Int(event.endDate.timeIntervalSince(event.startDate) / 60))
        let title = "status_bar_submenu_duration_all_day".loco(
            time.start,
            time.formatter.string(from: event.endDate),
            durationMinutes
        )
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventCalendar(to menu: NSMenu, event: MBEvent) {
        guard state.hasMultipleSelectedCalendars else { return }

        menu.addItem(
            withTitle: "status_bar_submenu_calendar_title".loco(event.calendar.title),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventLocation(to menu: NSMenu, event: MBEvent) {
        guard let location = event.location, !location.isEmpty else { return }

        menu.addItem(
            withTitle: "status_bar_submenu_location_title".loco(),
            action: nil,
            keyEquivalent: ""
        )
        let locationItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        locationItem.view = createNSViewFromText(text: location, maxWidth: 420)
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventOrganizer(to menu: NSMenu, event: MBEvent) {
        guard let organizer = event.organizer else { return }

        menu.addItem(
            withTitle: "status_bar_submenu_organizer_title".loco(organizer.name),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventNotes(to menu: NSMenu, event: MBEvent) {
        guard let rawNotes = event.notes else { return }
        let notes = cleanUpNotes(rawNotes)
        guard !notes.isEmpty else { return }

        menu.addItem(
            withTitle: "status_bar_submenu_notes_title".loco(),
            action: nil,
            keyEquivalent: ""
        )
        let notesItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        notesItem.view = createNSViewFromText(text: notes, maxWidth: 420)
        menu.addItem(NSMenuItem.separator())
    }

    private func addEventAttendees(to menu: NSMenu, event: MBEvent) {
        guard !event.attendees.isEmpty else { return }

        let attendees = event.attendees.sorted { $0.status.rawValue < $1.status.rawValue }
        menu.addItem(
            withTitle: "status_bar_submenu_attendees_title".loco(attendees.count),
            action: nil,
            keyEquivalent: ""
        )
        for attendee in attendees {
            menu.addItem(makeAttendeeItem(attendee))
        }
        menu.addItem(NSMenuItem.separator())
    }

    private func makeAttendeeItem(_ attendee: MBEventAttendee) -> NSMenuItem {
        var attributes: [NSAttributedString.Key: Any] = [:]
        let name = attendee.isCurrentUser
            ? "status_bar_submenu_attendees_you".loco(attendee.name)
            : attendee.name
        let roleMark = attendee.optional ? "*" : ""

        let status: String
        switch attendee.status {
        case .declined:
            status = ""
            attributes[.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
        case .tentative:
            status = "status_bar_submenu_attendees_status_tentative".loco()
        case .pending:
            status = "status_bar_submenu_attendees_status_unknown".loco()
        default:
            status = ""
        }

        let title = "- \(name)\(roleMark) \(status)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        return item
    }

    private func addEventActions(to menu: NSMenu, event: MBEvent) {
        if let alternateLinksItem = makeAlternateMeetingLinksMenu(for: event) {
            menu.addItem(alternateLinksItem)
        }

        if event.meetingLink != nil {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_copy_meeting_link".loco(),
                action: #selector(StatusBarItemController.copyEventMeetingLink),
                representedObject: event
            )
        }

        if isDismissed(event) {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_undismiss_meeting".loco(),
                action: #selector(StatusBarItemController.undismissEvent),
                representedObject: event
            )
        } else {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_dismiss_meeting".loco(),
                action: #selector(StatusBarItemController.dismissEvent),
                representedObject: event
            )
        }

        addEventAction(
            to: menu,
            title: "status_bar_submenu_email_attendees".loco(),
            action: #selector(StatusBarItemController.emailAttendees),
            representedObject: event
        )
        // Only offer "Open in Calendar" when the source provides a usable URL
        // (EventKit: ical://ekevent/…, Google: htmlLink). Hidden otherwise so we
        // never open a broken ical:// link for a Google event id.
        if let calendarOpenURL = event.calendarOpenURL {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_open_in_calendar".loco(),
                action: #selector(StatusBarItemController.openEventInCalendar),
                representedObject: calendarOpenURL
            )
        }

        if isFantasticalInstalled {
            addEventAction(
                to: menu,
                title: "status_bar_submenu_open_in_fantastical".loco(),
                action: #selector(StatusBarItemController.openEventInFantastical),
                representedObject: event
            )
        }
    }

    private func addEventAction(
        to menu: NSMenu,
        title: String,
        action: Selector,
        representedObject: Any
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = representedObject
    }

    private func isDismissed(_ event: MBEvent) -> Bool {
        state.events.dismissedEvents.contains { $0.id == event.id }
    }

    private func makeAlternateMeetingLinksMenu(for event: MBEvent) -> NSMenuItem? {
        guard !event.alternateMeetingLinkCandidates.isEmpty else { return nil }

        let title = "status_bar_join_with_other_link".loco()
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for candidate in event.alternateMeetingLinkCandidates {
            let alternateItem = menu.addItem(
                withTitle: alternateMeetingLinkTitle(for: candidate),
                action: #selector(StatusBarItemController.joinMeetingLinkCandidate),
                keyEquivalent: ""
            )
            alternateItem.target = target
            alternateItem.representedObject = candidate
            alternateItem.toolTip = candidate.url.absoluteString
        }
        item.submenu = menu
        return item
    }

    private func alternateMeetingLinkTitle(for candidate: MeetingLinkCandidate) -> String {
        let service = candidate.service?.localizedValue ?? "constants_meeting_service_other".loco()
        guard let host = candidate.url.host else { return service }
        return "\(service) - \(host)"
    }
}
