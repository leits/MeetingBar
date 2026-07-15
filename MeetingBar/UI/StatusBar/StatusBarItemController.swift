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
            .showEventCalendarColor,
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

    func renderStatusBar(_ presentation: StatusBarPresentation) {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = nil
        button.setAccessibilityLabel(nil)
        button.alignment = .center
        button.cell?.lineBreakMode = .byTruncatingTail

        let iconImage: NSImage?
        switch presentation.icon {
        case .asset(let name):
            iconImage = MenuStyleConstants.iconNamed(name)
        case .meetingService(let service):
            iconImage = getIconForMeetingService(service)
        case .none:
            iconImage = nil
        }
        iconImage?.size = MenuStyleConstants.iconSize
        // "no_online_session" is the sentinel asset meaning "show no icon".
        let hasNoSessionIcon = iconImage?.name() == "no_online_session"

        // Stacked layout (title over countdown): NSStatusBarButton is an NSButton
        // whose cell only reliably centers a SINGLE line — a two-line
        // attributedTitle is top-aligned/off-center and can only be faked with
        // brittle, per-machine magic numbers. Instead we draw the icon and both
        // lines into one image and center it ourselves against the real menu-bar
        // height. The button centers a single image by its bounds, so this is
        // correct on every menu-bar height, macOS version and display scale.
        if presentation.mode == .nextEvent, presentation.layout == .stacked,
           !(presentation.title.isEmpty && presentation.time.isEmpty) {
            button.image = StatusBarTitleRenderer.stackedImage(
                title: presentation.title,
                time: presentation.time,
                icon: hasNoSessionIcon ? nil : iconImage,
                style: presentation.titleStyle
            )
            button.imagePosition = .imageOnly
            button.toolTip = presentation.tooltip
            // VoiceOver reads the full (untruncated) title; the visible title may be shortened.
            button.setAccessibilityLabel("\(presentation.tooltip ?? presentation.title), \(presentation.time)")
            ensureStatusBarButtonIsVisible(button)
            return
        }

        button.image = iconImage
        button.imagePosition = hasNoSessionIcon ? .noImage : .imageLeft

        if presentation.mode == .nextEvent {
            button.attributedTitle = StatusBarTitleRenderer.attributedTitle(for: presentation)
            button.toolTip = presentation.tooltip
        }

        ensureStatusBarButtonIsVisible(button)
    }

    private func ensureStatusBarButtonIsVisible(_ button: NSStatusBarButton) {
        guard button.image == nil,
              button.title.isEmpty,
              button.attributedTitle.string.isEmpty
        else { return }

        button.image = MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName)
        button.image?.size = MenuStyleConstants.iconSize
        button.imagePosition = .imageLeft
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

        statusItemMenu.items += builder.buildTopSection()

        if menuState.hasSelectedCalendars {
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

            switch menuState.events.showEventsForPeriod {
            case .today:
                statusItemMenu.items += builder.buildDateSection(
                    date: today, title: "status_bar_section_today".loco(),
                    events: menuState.todayEvents,
                    subdueEmptyState: menuState.todayEvents.isEmpty
                        && !menuState.tomorrowEvents.isEmpty
                )
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
        statusItemMenu.items += builder.buildJoinSection(
            nextEvent: menuState.nextEvent,
            includeJoinAction: false
        )

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
    func joinEvent(sender: NSMenuItem) {
        guard let event = sender.representedObject as? MBEvent else {
            AppMessageCenter.shared.post(.nextMeetingMissing)
            return
        }
        dependencies.send(.joinMeeting(eventID: event.id))
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
            // The stacked layout is drawn as a self-centered image in
            // StatusBarItemController.renderStatusBar (NSStatusBarButton cannot
            // vertically center a multi-line title), so it never routes through here.
            return NSAttributedString(string: "")
        }
    }

    /// Renders the icon plus the two stacked lines (title over countdown) into a
    /// single image, vertically centered within the menu bar (using at least the
    /// current menu-bar height). Used instead of a two-line `attributedTitle`
    /// because `NSStatusBarButton`'s cell does not vertically center multi-line
    /// titles.
    ///
    /// Text uses dynamic system colors and *template* icons (e.g. the calendar
    /// icon) are tinted at draw time, so the image adapts to the menu bar's
    /// light/dark appearance; colored (non-template) meeting-service icons are
    /// preserved as-is. `cacheMode = .never` guarantees the drawing handler re-runs
    /// on every draw so an appearance change is picked up immediately.
    static func stackedImage(
        title: String,
        time: String,
        icon: NSImage?,
        style: StatusBarTitleStyle
    ) -> NSImage {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        // Reuse the inline styling (inactive colour, dotted underline); add the
        // paragraph and an explicit label colour for the .normal/.underlined cases
        // that the helper leaves to the control's default.
        var titleAttrs = titleAttributes(style: style, font: NSFont.systemFont(ofSize: 11))
        titleAttrs[.paragraphStyle] = paragraph
        if titleAttrs[.foregroundColor] == nil {
            titleAttrs[.foregroundColor] = NSColor.labelColor
        }
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        let titleString = NSAttributedString(string: title, attributes: titleAttrs)
        let timeString = NSAttributedString(string: time, attributes: timeAttrs)

        // Cap the measured width so very long titles truncate rather than growing
        // the status item without bound.
        let maxTextWidth: CGFloat = 260
        let measure: (NSAttributedString) -> NSSize = { string in
            let rect = string.boundingRect(
                with: NSSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return NSSize(width: ceil(rect.width), height: ceil(rect.height))
        }
        let titleSize = measure(titleString)
        let timeSize = measure(timeString)

        // An empty string still measures to a full line height, so treat a blank
        // line as absent (zero height). Otherwise the space reserved for the
        // missing line pushes the remaining line off true center.
        let titleHeight = title.isEmpty ? 0 : titleSize.height
        let timeHeight = time.isEmpty ? 0 : timeSize.height

        // Overlap the two lines' leading so the block is compact. `draw(with:)` does
        // not clip glyphs to their rect, so positioning the rects closer than their
        // natural heights just tightens the line spacing. Only applied when both
        // lines are present so a single line stays centered.
        let overlap: CGFloat = (title.isEmpty || time.isEmpty) ? 0 : 4
        let blockHeight = titleHeight + timeHeight - overlap

        let iconSize = icon?.size ?? .zero
        let iconGap: CGFloat = icon == nil ? 0 : 3
        let textWidth = max(titleSize.width, timeSize.width)
        // Clamp so tall scripts or a thinner-than-expected bar never clip the glyphs.
        let height = max(NSStatusBar.system.thickness, ceil(blockHeight))
        let width = ceil(iconSize.width + iconGap + textWidth)

        let textX = iconSize.width + iconGap
        let blockBottom = ((height - blockHeight) / 2).rounded()

        // Copy the icon: iconNamed / getIconForMeetingService return shared named
        // NSImage instances and the drawing handler may run off the main thread.
        let iconCopy = icon?.copy() as? NSImage

        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            if let iconCopy {
                let iconRect = NSRect(
                    x: 0, y: ((height - iconSize.height) / 2).rounded(),
                    width: iconSize.width, height: iconSize.height
                )
                iconCopy.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                if iconCopy.isTemplate {
                    // Tint template icons to the resolved menu-bar text color.
                    NSColor.labelColor.set()
                    iconRect.fill(using: .sourceAtop)
                }
            }
            // Non-flipped context (y grows up): countdown at the bottom of the
            // block, title above it. Each string draws in a rect of its measured
            // size so `.usesLineFragmentOrigin` fills it from the top down. A blank
            // line is skipped and contributes no height (see titleHeight/timeHeight).
            if !time.isEmpty {
                timeString.draw(
                    with: NSRect(x: textX, y: blockBottom, width: textWidth, height: timeSize.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
            }
            if !title.isEmpty {
                titleString.draw(
                    with: NSRect(x: textX, y: blockBottom + timeHeight - overlap,
                                 width: textWidth, height: titleSize.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
            }
            return true
        }
        image.isTemplate = false
        image.cacheMode = .never
        return image
    }

    private static func titleAttributes(
        style: StatusBarTitleStyle,
        font: NSFont
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
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
