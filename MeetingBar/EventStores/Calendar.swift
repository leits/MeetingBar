//
//  Calendar.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 09.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit

final public class MBCalendar: Hashable, Sendable {
    let title: String
    let ID: String
    let source: String
    let email: String?
    let color: NSColor

    init(title: String, ID: String, source: String?, email: String?, color: NSColor) {
        self.title = title
        self.ID = ID
        self.source = source ?? "unknown"
        self.email = email
        self.color = color
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ID)
    }

    static func == (lhs: MBCalendar, rhs: MBCalendar) -> Bool {
        lhs.ID == rhs.ID
    }
}
