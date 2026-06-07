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

    /// Loads a named asset; if the asset is missing or has been renamed,
    /// falls back to the bundle's runtime app icon and finally to a 1x1
    /// placeholder so the menu bar never crashes on a misconfigured Defaults
    /// value or a renamed asset.
    static func iconNamed(_ name: String) -> NSImage {
        if let image = NSImage(named: name) {
            return image
        }
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            return appIcon
        }
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}

struct StatusBarDependencies {
    var appState: @MainActor () -> AppState = { AppState() }
    var events: @MainActor () -> [MBEvent] = { [] }
    var send: @MainActor (AppAction) -> Void = { _ in }
    var openPreferences: @MainActor () -> Void = {}
    var openChangelog: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
}

/// creates the menu in the system status bar, creates the menu items and controls the whole lifecycle.
@MainActor
final class StatusBarItemController {
    var statusItem: NSStatusItem!
    var statusItemMenu: NSMenu!

    /// Current event list, driven by the AppModel state.
    /// A non-nil `_eventsOverride` takes precedence (used by tests to inject
    /// events without wiring up the full app model chain).
    private var _eventsOverride: [MBEvent]?
    var events: [MBEvent] {
        get { _eventsOverride ?? dependencies.events() }
        set { _eventsOverride = newValue }
    }

    let installationDate = getInstallationDate()

    private var dependencies = StatusBarDependencies()

    private var cancellables = Set<AnyCancellable>()

    init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItemMenu = NSMenu(title: "MeetingBar in Status Bar Menu")

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusMenuBarAction)
        statusItem.button?.sendAction(on: [
            NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseUp,
            NSEvent.EventTypeMask.leftMouseDown
        ])

        // Temporary icon and menu before app delegate setup
        statusItem.button?.image = MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName)
        statusItem.button?.image?.size = MenuStyleConstants.iconSize
        statusItem.button?.imagePosition = .imageLeft
        let menuItem = statusItemMenu.addItem(
            withTitle: "window_title_onboarding".loco(), action: nil, keyEquivalent: "")
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
                self?.reconcileNotifications()
            }
            .store(in: &cancellables)

        Defaults.publisher(.preferredLanguage, options: [.initial])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if I18N.instance.changeLanguage(to: change.newValue) {
                    self?.updateMenu()
                    self?.updateTitle()
                    self?.reconcileNotifications()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(
            keys: .joinEventNotification,
            .joinEventNotificationTime,
            .endOfEventNotification,
            .endOfEventNotificationTime,
            .fullscreenNotification,
            .fullscreenNotificationTime,
            .fullscreenNotificationsForEventsWithoutMeetingLink,
            .automaticEventJoin,
            .automaticEventJoinTime,
            .runEventStartScript,
            .eventStartScriptTime,
            .eventStartScriptLocation,
            .dismissedEvents,
            options: []
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.reconcileNotifications()
        }
        .store(in: &cancellables)
    }

    private func reconcileNotifications() {
        dependencies.send(.reconcileNotifications)
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
            Task { @MainActor in self.dependencies.send(.toggleMeetingTitleVisibility) }
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
        statusItem.button?.performClick(nil)  // ...and click
        statusItem.menu = nil
    }

    func configure(dependencies: StatusBarDependencies) {
        self.dependencies = dependencies
    }

    func updateTitle() {
        let now = Date()
        let presentation = StatusBarPresenter.presentation(
            nextEvent: events.nextEvent().map(StatusBarEventPresentationInput.init),
            settings: .current,
            now: now,
            calendar: statusBarCalendar()
        )

        if presentation.removeDeliveredNotifications, Defaults[.joinEventNotification] {
            removeDeliveredNotifications()
        }

        renderStatusBar(presentation)
    }

    private func renderStatusBar(_ presentation: StatusBarPresentation) {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = nil
        button.alignment = .center
        button.cell?.lineBreakMode = .byTruncatingTail

        switch presentation.icon {
        case .asset(let name):
            button.image = MenuStyleConstants.iconNamed(name)
        case .meetingService(let service):
            button.image = getIconForMeetingService(service)
        case .none:
            break
        }
        button.image?.size = MenuStyleConstants.iconSize
        button.imagePosition = button.image?.name() == "no_online_session" ? .noImage : .imageLeft

        guard presentation.mode == .nextEvent else { return }
        button.attributedTitle = StatusBarTitleRenderer.attributedTitle(for: presentation)
        button.toolTip = presentation.tooltip
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

        var appState = dependencies.appState()
        appState.events = events
        let menuState = StatusBarMenuState.make(from: appState)
        let builder = MenuBuilder(
            target: self, state: menuState, installationDate: installationDate)

        statusItemMenu.autoenablesItems = false
        statusItemMenu.removeAllItems()

        statusItemMenu.items += builder.buildMeetingControlSection()
        statusItemMenu.addItem(NSMenuItem.separator())

        if menuState.hasSelectedCalendars {
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

            if menuState.showTimeline, !menuState.todayEvents.isEmpty {
                let segments = menuState.todayEvents.map {
                    DaySegment(
                        start: max($0.startDate, today),
                        end: min($0.endDate, tomorrow),
                        color: Color($0.calendar.color))
                }

                let timeline = DayRelativeTimelineView(
                    segments: segments,
                    currentDate: Date(),
                    timeFormat: menuState.timeFormat)
                let hosting = NSHostingView(rootView: timeline)
                hosting.autoresizingMask = [.width]
                hosting.frame.size.height = timeline.preferredHeight

                let item = NSMenuItem()
                item.view = hosting
                statusItemMenu.addItem(item)
                statusItemMenu.addItem(.separator())
            }

            switch menuState.events.showEventsForPeriod {
            case .today:
                statusItemMenu.items += builder.buildDateSection(
                    date: today, title: "status_bar_section_today".loco(),
                    events: menuState.todayEvents)
            case .today_n_tomorrow:
                statusItemMenu.items += builder.buildDateSection(
                    date: today, title: "status_bar_section_today".loco(),
                    events: menuState.todayEvents)

                statusItemMenu.addItem(NSMenuItem.separator())

                statusItemMenu.items += builder.buildDateSection(
                    date: tomorrow, title: "status_bar_section_tomorrow".loco(),
                    events: menuState.tomorrowEvents)
            }
        }
        statusItemMenu.addItem(NSMenuItem.separator())
        statusItemMenu.items += builder.buildJoinSection(nextEvent: nil)

        if !menuState.meetings.bookmarks.isEmpty {
            statusItemMenu.addItem(NSMenuItem.separator())
            statusItemMenu.items += builder.buildBookmarksSection(bookmarks: menuState.meetings.bookmarks)
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
            dependencies.send(.joinMeeting(eventID: nextEvent.id))
        } else {
            AppMessageCenter.shared.post(.nextMeetingMissing)
        }
    }

    @objc
    func dismissNextMeetingAction() {
        if let nextEvent = events.nextEvent() {
            dependencies.send(.dismissMeeting(eventID: nextEvent.id))
            AppMessageCenter.shared.post(.meetingDismissed(title: nextEvent.title))

            updateTitle()
            updateMenu()
            reconcileNotifications()
        }
    }

    @objc
    func undismissMeetingsActions() {
        dependencies.send(.clearDismissedMeetings)
        AppMessageCenter.shared.post(.allDismissalsRemoved)

        updateTitle()
        updateMenu()
        reconcileNotifications()
    }

    @objc
    func openLinkFromClipboardAction() {
        openLinkFromClipboard()
    }

    @objc
    func toggleMeetingTitleVisibility() {
        dependencies.send(.toggleMeetingTitleVisibility)
    }

    @objc
    func rateApp() {
        Links.rateAppInAppStore.openInDefaultBrowser()
    }

    @objc
    func joinBookmark(sender: NSMenuItem) {
        if let bookmark: Bookmark = sender.representedObject as? Bookmark {
            MeetingOpener.open(
                meetingLink: MeetingLink(service: MeetingServices(rawValue: bookmark.service), url: bookmark.url))
        }
    }

    @objc
    func clickOnEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            dependencies.send(.joinMeeting(eventID: event.id))
        }
    }

    @objc
    func joinMeetingLinkCandidate(sender: NSMenuItem) {
        if let candidate = sender.representedObject as? MeetingLinkCandidate {
            MeetingOpener.open(
                meetingLink: MeetingLink(service: candidate.service, url: candidate.url))
        }
    }

    @objc
    func openEventInCalendar(sender: NSMenuItem) {
        // The menu attaches the provider-specific calendar URL directly
        // (ical://ekevent/… for EventKit, htmlLink for Google).
        if let url = sender.representedObject as? URL {
            url.openInDefaultBrowser()
        }
    }

    @objc func handleManualRefresh() {
        dependencies.send(.refreshCalendars)
    }

    @objc func reconnectProviderAction() {
        dependencies.send(.changeProvider(stateProvider, signOut: true))
    }

    @objc func openCalendarPermissionsAction() {
        NSWorkspace.shared.open(Links.calendarPreferences)
    }

    @objc
    func dismissEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            dismiss(event: event)
        }
    }

    func dismiss(event: MBEvent) {
        dependencies.send(.dismissMeeting(eventID: event.id))

        updateTitle()
        updateMenu()
        reconcileNotifications()
    }

    @objc
    func undismissEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            dependencies.send(.undismissMeeting(eventID: event.id))

            updateTitle()
            updateMenu()
            reconcileNotifications()
        }
    }

    @objc
    func copyEventMeetingLink(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            if let meetingLink = event.meetingLink {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(meetingLink.url.absoluteString, forType: .string)
            } else {
                AppMessageCenter.shared.post(.meetingLinkMissing(title: event.title))
            }
        }
    }

    @objc
    func emailAttendees(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            MeetingOpener.emailAttendees(for: event)
        }
    }

    @objc
    func openEventInFantastical(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            openInFantastical(startDate: event.startDate, title: event.title)
        }
    }

    @objc
    func openPreferencesAction() {
        dependencies.openPreferences()
    }

    private var stateProvider: EventStoreProvider {
        dependencies.appState().activeProvider
    }

    @objc
    func openChangelogAction() {
        dependencies.openChangelog()
    }

    @objc
    func quitAction() {
        dependencies.quit()
    }
}

@MainActor
enum StatusBarTitleRenderer {
    static func attributedTitle(for presentation: StatusBarPresentation) -> NSAttributedString {
        switch presentation.layout {
        case .none:
            return NSAttributedString(string: "")
        case .inline(let showTime):
            var eventTitle = presentation.title
            if showTime {
                eventTitle += " " + presentation.time
            }
            return NSAttributedString(
                string: eventTitle,
                attributes: titleAttributes(
                    style: presentation.titleStyle,
                    font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize)
                )
            )
        case .stacked:
            return stackedTitle(for: presentation)
        }
    }

    private static func stackedTitle(for presentation: StatusBarPresentation) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: presentation.title,
            attributes: titleAttributes(
                style: presentation.titleStyle,
                font: NSFont.systemFont(ofSize: 12),
                baselineOffset: -3
            )
        )
        title.append(
            NSAttributedString(
                string: "\n" + presentation.time,
                attributes: [
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: 9),
                    NSAttributedString.Key.foregroundColor: NSColor.lightGray
                ]
            ))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.7
        paragraphStyle.alignment = .center
        title.addAttributes(
            [NSAttributedString.Key.paragraphStyle: paragraphStyle],
            range: NSRange(location: 0, length: title.length)
        )
        return title
    }

    private static func titleAttributes(
        style: StatusBarTitleStyle,
        font: NSFont,
        baselineOffset: CGFloat? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        if let baselineOffset {
            attributes[.baselineOffset] = baselineOffset
        }
        switch style {
        case .normal:
            break
        case .inactive:
            attributes[.foregroundColor] = NSColor.disabledControlTextColor
        case .underlined:
            attributes[.underlineStyle] =
                NSUnderlineStyle.single.rawValue
                | NSUnderlineStyle.patternDot.rawValue
                | NSUnderlineStyle.byWord.rawValue
        }
        return attributes
    }
}

private func statusBarCalendar() -> Calendar {
    var calendar = Calendar.current
    calendar.locale = I18N.instance.locale
    return calendar
}

enum NextEventState {
    case none
    case afterThreshold(MBEvent)
    case nextEvent(MBEvent)
}
