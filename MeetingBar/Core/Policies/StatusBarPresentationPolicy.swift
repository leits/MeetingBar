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
