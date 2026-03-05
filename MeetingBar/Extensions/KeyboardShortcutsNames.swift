//
//  KeyboardShortcutsNames.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import KeyboardShortcuts

extension KeyboardShortcuts.Name: @unchecked @retroactive Sendable {}

extension KeyboardShortcuts.Name {
    /// Global shortcut used to create an ad-hoc meeting.
    static let createMeetingShortcut = Self("createMeetingShortcut")
    /// Global shortcut used to open the status bar menu.
    static let openMenuShortcut = Self("openMenuShortcut")
    /// Global shortcut used to join the nearest meeting (current or next).
    static let joinEventShortcut = Self("joinEventShortcut")
    /// Global shortcut used to join only the currently running meeting.
    static let joinCurrentEventShortcut = Self("joinCurrentEventShortcut")
    /// Global shortcut used to open a meeting link from clipboard.
    static let openClipboardShortcut = Self("openClipboardShortcut")
    /// Global shortcut used to toggle status bar meeting title visibility.
    static let toggleMeetingTitleVisibilityShortcut = Self("toggleMeetingTitleVisibilityShortcut")
}
