//
//  MBEvent+Helpers.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Defaults
import Foundation

public extension Array where Element == MBEvent {
    /// Returns only those events that pass all the user’s Defaults filters.
    func filtered() -> [MBEvent] {
        let candidates = enumerated().map { index, event in
            EventFilterEvent(event: event, sourceIndex: index)
        }
        return EventFiltering
            .filter(candidates, settings: .current)
            .map { self[$0.sourceIndex] }
    }

    /// From a pre-filtered, sorted array, find the nearest upcoming MBEvent.
    func nextEvent(linkRequired: Bool = false) -> MBEvent? {
        let candidates = enumerated().map { index, event in
            EventSelectionEvent(event: event, sourceIndex: index)
        }
        guard let selected = EventSelection.nextEvent(
            from: candidates,
            linkRequired: linkRequired,
            settings: .current,
            now: Date()
        ) else {
            return nil
        }
        return self[selected.sourceIndex]
    }
}
