//
//  Calendar.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 09.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit

public struct MBCalendar: Hashable, Sendable {
    let title: String
    let id: String
    let source: String
    let email: String?
    let color: NSColor

    init(title: String, id: String, source: String?, email: String?, color: NSColor) {
        self.title = title
        self.id = id
        self.source = source ?? "unknown"
        self.email = email
        self.color = color
    }
}
