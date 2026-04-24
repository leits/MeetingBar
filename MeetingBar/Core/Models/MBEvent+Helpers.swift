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
        EventFilterPolicy.filter(self, settings: .current)
    }

    /// From a pre-filtered, sorted array, find the nearest upcoming MBEvent.
    func nextEvent(linkRequired: Bool = false) -> MBEvent? {
        EventSelectionPolicy.nextEvent(
            from: self,
            linkRequired: linkRequired,
            settings: .current,
            now: Date()
        )
    }
}
