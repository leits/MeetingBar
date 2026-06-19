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
