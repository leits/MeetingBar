//
//  StatusBarPresentationPolicy.swift
//  MeetingBar
//

import Foundation

/// Per-event-list settings the status bar presentation policy needs.
///
/// Constructed at the call site from `Defaults` so the policy itself stays
/// pure and testable.
struct StatusBarPresentationSettings: Equatable {
    let hasSelectedCalendars: Bool
    let showEventMaxTimeUntilEventEnabled: Bool
    /// Threshold in minutes — events starting more than this far in the future
    /// are rendered as "afterThreshold" when the toggle is on.
    let showEventMaxTimeUntilEventThreshold: Int
}

/// Coarse classification of what the status bar should show. Used to drive
/// the title text, icon and tooltip in `StatusBarItemController.updateTitle`.
enum StatusBarTitleMode: Equatable {
    /// User has not selected any calendars yet — render the app icon.
    case idle
    /// Calendars are selected, but no upcoming event matches the current
    /// filters — render the "done for today" icon.
    case noUpcoming
    /// An upcoming event exists and should be rendered with its title.
    case nextEvent
    /// An upcoming event exists but starts beyond the configured threshold.
    /// Render an "alarm clock" hint instead of the event title.
    case afterThreshold
}

enum StatusBarTimeDisplay: Equatable {
    case show
    case showUnderTitle
    case hide
}

enum StatusBarEventParticipation: Equatable {
    case normal
    case pending
    case tentative
}

enum StatusBarParticipationDisplay: Equatable {
    case normal
    case inactive
    case underlined
}

enum StatusBarTitleLayout: Equatable {
    case none
    case inline(showTime: Bool)
    case stacked
}

enum StatusBarTitleStyle: Equatable {
    case normal
    case inactive
    case underlined
}

struct StatusBarEventPresentationInput: Equatable {
    let title: String?
    let startDate: Date
    let endDate: Date
    let meetingService: MeetingServices?
    let participation: StatusBarEventParticipation
}

struct StatusBarPresenterSettings: Equatable {
    let presentation: StatusBarPresentationSettings
    let title: StatusBarTitleSettings
    let timeDisplay: StatusBarTimeDisplay
    let iconFormat: StatusBarIconFormat
    let iconFormatAssetName: String
    let iconAssets: StatusBarIconAssets
    let pendingDisplay: StatusBarParticipationDisplay
    let tentativeDisplay: StatusBarParticipationDisplay
    let compactTitleLimit: Int
}

struct StatusBarPresentation: Equatable {
    let mode: StatusBarTitleMode
    let title: String
    let time: String
    let tooltip: String?
    let icon: StatusBarIcon
    let layout: StatusBarTitleLayout
    let titleStyle: StatusBarTitleStyle
    let compactFallback: Bool
    let removeDeliveredNotifications: Bool
}

/// Picks the status bar mode for the current next-event candidate.
///
/// Pure: takes the next event's `startDate` (not the full `MBEvent`) plus a
/// settings snapshot. The renderer already has the `MBEvent`, so the policy
/// does not need to thread it through.
enum StatusBarPresentationPolicy {
    static func mode(
        nextEventStartDate: Date?,
        settings: StatusBarPresentationSettings,
        now: Date
    ) -> StatusBarTitleMode {
        guard settings.hasSelectedCalendars else { return .idle }
        guard let startDate = nextEventStartDate else { return .noUpcoming }
        guard settings.showEventMaxTimeUntilEventEnabled else { return .nextEvent }
        let timeUntilStart = startDate.timeIntervalSince(now)
        let thresholdInSeconds = TimeInterval(settings.showEventMaxTimeUntilEventThreshold * 60)
        return timeUntilStart < thresholdInSeconds ? .nextEvent : .afterThreshold
    }
}

enum StatusBarPresenter {
    static func presentation(
        nextEvent: StatusBarEventPresentationInput?,
        settings: StatusBarPresenterSettings,
        now: Date,
        calendar: Calendar
    ) -> StatusBarPresentation {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: nextEvent?.startDate,
            settings: settings.presentation,
            now: now
        )

        guard mode == .nextEvent, let nextEvent else {
            return StatusBarPresentation(
                mode: mode,
                title: "",
                time: "",
                tooltip: nil,
                icon: nonEventIcon(mode: mode, settings: settings),
                layout: .none,
                titleStyle: .normal,
                compactFallback: false,
                removeDeliveredNotifications: mode == .noUpcoming
            )
        }

        let rawTitleCount = nextEvent.title?.count ?? 0
        let needsCompactTitle = settings.title.titleFormat == .show
            && !settings.title.hideMeetingTitle
            && rawTitleCount > settings.compactTitleLimit
        let titleSettings = needsCompactTitle
            ? StatusBarTitleSettings(
                titleFormat: settings.title.titleFormat,
                hideMeetingTitle: settings.title.hideMeetingTitle,
                titleLength: settings.compactTitleLimit,
                labels: settings.title.labels
            )
            : settings.title
        let text = StatusBarTitlePolicy.text(
            eventTitle: nextEvent.title,
            startDate: nextEvent.startDate,
            endDate: nextEvent.endDate,
            settings: titleSettings,
            now: now,
            calendar: calendar
        )

        var icon = StatusBarIconPolicy.icon(
            mode: mode,
            format: settings.iconFormat,
            formatAssetName: settings.iconFormatAssetName,
            meetingService: nextEvent.meetingService,
            assets: settings.iconAssets
        )
        var title = text.title
        var compactFallback = false

        if (needsCompactTitle && icon == .none) || (title.isEmpty && icon == .none) {
            icon = .meetingService(nextEvent.meetingService)
            if title.isEmpty {
                title = "•"
            }
            compactFallback = true
        }

        return StatusBarPresentation(
            mode: mode,
            title: title,
            time: text.time,
            tooltip: nextEvent.title,
            icon: icon,
            layout: titleLayout(timeDisplay: settings.timeDisplay, titleFormat: settings.title.titleFormat),
            titleStyle: titleStyle(
                participation: nextEvent.participation,
                layout: titleLayout(timeDisplay: settings.timeDisplay, titleFormat: settings.title.titleFormat),
                pendingDisplay: settings.pendingDisplay,
                tentativeDisplay: settings.tentativeDisplay
            ),
            compactFallback: compactFallback,
            removeDeliveredNotifications: false
        )
    }

    private static func nonEventIcon(
        mode: StatusBarTitleMode,
        settings: StatusBarPresenterSettings
    ) -> StatusBarIcon {
        StatusBarIconPolicy.icon(
            mode: mode,
            format: settings.iconFormat,
            formatAssetName: settings.iconFormatAssetName,
            meetingService: nil,
            assets: settings.iconAssets
        )
    }

    private static func titleLayout(
        timeDisplay: StatusBarTimeDisplay,
        titleFormat: StatusBarEventTitleFormat
    ) -> StatusBarTitleLayout {
        guard titleFormat != .none else {
            return timeDisplay == .showUnderTitle ? .inline(showTime: false) : .inline(showTime: timeDisplay == .show)
        }
        switch timeDisplay {
        case .show:
            return .inline(showTime: true)
        case .showUnderTitle:
            return .stacked
        case .hide:
            return .inline(showTime: false)
        }
    }

    private static func titleStyle(
        participation: StatusBarEventParticipation,
        layout: StatusBarTitleLayout,
        pendingDisplay: StatusBarParticipationDisplay,
        tentativeDisplay: StatusBarParticipationDisplay
    ) -> StatusBarTitleStyle {
        let display: StatusBarParticipationDisplay
        switch participation {
        case .normal:
            display = .normal
        case .pending:
            display = pendingDisplay
        case .tentative:
            display = tentativeDisplay
        }

        switch display {
        case .normal:
            return .normal
        case .inactive:
            return layout == .stacked ? .inactive : .normal
        case .underlined:
            return .underlined
        }
    }
}
