//
//  MBEvent+MeetingBar.swift
//  MeetingBar
//
//  Adapter layer: Defaults-reading helpers for the data-only MBEvent type.
//  These depend on AppKit and Defaults and must stay in the app target.
//

import AppKit
import Defaults

func getEventDateString(_ event: MBEvent) -> String {
    let eventTimeFormatter = DateFormatter()
    eventTimeFormatter.locale = I18N.instance.locale

    switch Defaults[.timeFormat] {
    case .am_pm:
        eventTimeFormatter.dateFormat = "h:mm a  "
    case .military:
        eventTimeFormatter.dateFormat = "HH:mm"
    }
    let eventStartTime = eventTimeFormatter.string(from: event.startDate)
    let eventEndTime = eventTimeFormatter.string(from: event.endDate)
    let eventDurationMinutes = String(Int(event.endDate.timeIntervalSince(event.startDate) / 60))
    return "status_bar_submenu_duration_all_day".loco(eventStartTime, eventEndTime, eventDurationMinutes)
}

// MARK: - Filtering / next-event helpers

public extension Array where Element == MBEvent {
    /// Deduplicates events by `id`, keeping the copy that actually resolved
    /// the current user's attendee entry.
    ///
    /// The same event can be fetched twice when it's visible through more
    /// than one selected calendar (e.g. a work calendar also subscribed to
    /// from a personal account). Both copies share the same event `id`, but
    /// only the copy fetched through the calendar the user was actually
    /// invited on resolves their attendee record — the other calendar's copy
    /// has no matching attendee, so its `participationStatus` falls back to
    /// `.unknown`/`.active` instead of the user's real RSVP. Picking whichever
    /// copy happened to be fetched first (as a plain `Dictionary` uniquing
    /// would) silently keeps the wrong one at random.
    func deduplicatedPreferringResolvedAttendee() -> [MBEvent] {
        Array(Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, second in
            let firstResolved = first.attendees.contains { $0.isCurrentUser }
            let secondResolved = second.attendees.contains { $0.isCurrentUser }
            return (secondResolved && !firstResolved) ? second : first
        }).values)
    }

    /// Returns only those events that pass all the user's Defaults filters.
    func filtered() -> [MBEvent] {
        let candidates = enumerated().map { index, event in
            EventFilterEvent(event: event, sourceIndex: index)
        }
        return EventFiltering
            .filter(candidates, settings: .current)
            .map { self[$0.sourceIndex] }
    }

    /// From a pre-filtered, sorted array, find the nearest upcoming MBEvent.
    func nextEvent(linkRequired: Bool = false, now: Date = Date()) -> MBEvent? {
        let candidates = enumerated().map { index, event in
            EventSelectionEvent(event: event, sourceIndex: index)
        }
        guard let selected = EventSelection.nextEvent(
            from: candidates,
            linkRequired: linkRequired,
            settings: .current,
            now: now
        ) else {
            return nil
        }
        return self[selected.sourceIndex]
    }
}
