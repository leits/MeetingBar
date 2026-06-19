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

// MARK: - Title policy

enum StatusBarEventTitleFormat: Equatable {
    case show
    case dot
    case none
}

struct StatusBarTitleLabels: Equatable {
    let genericMeetingTitle: String
    let noTitle: String
    let activeEventTimeFormat: String
    let upcomingEventTimeFormat: String
}

struct StatusBarTitleSettings: Equatable {
    let titleFormat: StatusBarEventTitleFormat
    let hideMeetingTitle: Bool
    let titleLength: Int
    let labels: StatusBarTitleLabels
}

struct StatusBarTitleText: Equatable {
    let title: String
    let time: String
    let isActiveEvent: Bool
}

enum StatusBarTitlePolicy {
    // swiftlint:disable:next function_parameter_count
    static func text(
        eventTitle rawTitle: String?,
        startDate: Date,
        endDate: Date,
        settings: StatusBarTitleSettings,
        now: Date,
        calendar: Calendar
    ) -> StatusBarTitleText {
        let title = formattedTitle(rawTitle, settings: settings)
        let isActiveEvent = startDate <= now && endDate > now
        let eventDate = isActiveEvent ? endDate : startDate
        let timeLeft = formattedTimeLeft(from: now.addingTimeInterval(-60), to: eventDate, calendar: calendar)
        let timeFormat = isActiveEvent ? settings.labels.activeEventTimeFormat : settings.labels.upcomingEventTimeFormat
        let time = String(format: timeFormat, timeLeft)
        return StatusBarTitleText(title: title, time: time, isActiveEvent: isActiveEvent)
    }

    static func shortenTitle(_ rawTitle: String?, limit: Int, noTitle: String) -> String {
        var eventTitle = String(rawTitle ?? noTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0 else { return "..." }
        if eventTitle.count > limit {
            let index = eventTitle.index(eventTitle.startIndex, offsetBy: limit - 1)
            eventTitle = String(eventTitle[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
            eventTitle += "..."
        }
        return eventTitle
    }

    private static func formattedTitle(_ rawTitle: String?, settings: StatusBarTitleSettings) -> String {
        switch settings.titleFormat {
        case .show:
            if settings.hideMeetingTitle {
                return settings.labels.genericMeetingTitle
            }
            return shortenTitle(
                rawTitle,
                limit: settings.titleLength,
                noTitle: settings.labels.noTitle
            )
            .replacingOccurrences(of: "\n", with: " ")
        case .dot:
            return "•"
        case .none:
            return ""
        }
    }

    static func formattedTimeLeft(from start: Date, to end: Date, calendar: Calendar) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .hour, .day]
        formatter.calendar = calendar
        return formatter.string(from: start, to: end) ?? ""
    }
}

// MARK: - Icon policy

/// Shadow of `EventTitleIconFormat` so the policy stays hostless. The
/// `+MeetingBar.swift` adapter converts from the production Defaults enum.
enum StatusBarIconFormat: Equatable {
    case calendar
    case appicon
    case eventtype
    case none
}

/// What the status bar should render as its icon.
///
/// `asset(name)` is loaded via `NSImage(named:)` by the renderer; the renderer
/// is expected to fall back to a safe placeholder when the asset is missing
/// (see `MenuStyleConstants.iconNamed(_:)`).
enum StatusBarIcon: Equatable {
    case asset(String)
    case meetingService(MeetingServices?)
    case none
}

/// Asset names the renderer needs. Passed in by the caller so the policy is
/// fully decoupled from `MenuStyleConstants` and easy to test.
struct StatusBarIconAssets: Equatable {
    let appIcon: String
    let calendarCheckmark: String
    let calendar: String
}

/// Picks the status bar icon based on the current title mode, the user's
/// chosen icon format, and (for `.eventtype` format on a real event) the
/// next event's meeting service.
///
/// Decision matrix:
///
/// | mode             | format                      | icon                |
/// | ---------------- | --------------------------- | ------------------- |
/// | idle             | (any)                       | app icon            |
/// | noUpcoming       | appicon                     | app icon            |
/// | noUpcoming       | calendar / eventtype / none | calendar-checkmark  |
/// | afterThreshold   | appicon                     | app icon            |
/// | afterThreshold   | calendar / eventtype / none | calendar            |
/// | nextEvent        | none                        | no icon             |
/// | nextEvent        | eventtype                   | meetingService(...) |
/// | nextEvent        | appicon / calendar          | named asset         |
enum StatusBarIconPolicy {
    static func icon(
        mode: StatusBarTitleMode,
        format: StatusBarIconFormat,
        formatAssetName: String,
        meetingService: MeetingServices?,
        assets: StatusBarIconAssets
    ) -> StatusBarIcon {
        switch mode {
        case .idle:
            return .asset(assets.appIcon)
        case .noUpcoming:
            return format == .appicon
                ? .asset(assets.appIcon)
                : .asset(assets.calendarCheckmark)
        case .afterThreshold:
            return format == .appicon
                ? .asset(assets.appIcon)
                : .asset(assets.calendar)
        case .nextEvent:
            switch format {
            case .none:
                return .none
            case .eventtype:
                return .meetingService(meetingService)
            case .appicon, .calendar:
                return .asset(formatAssetName)
            }
        }
    }
}
