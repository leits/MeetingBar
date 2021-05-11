//
//  UserActions.swift
//  MeetingBar
//
//  Created by Sergey Ryazanov on 30.04.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Foundation
import AppKit

final class UserActions {
    struct Action: Hashable, Codable {
        let localizedKey: String
        let action: Selector

        var localizedName: String {
            self.localizedKey.loco()
        }

        func performAction() {
            guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
                return
            }
            appDelegate.perform(self.action)
        }

        init(localizedKey: String, action: Selector) {
            self.localizedKey = localizedKey
            self.action = action
        }

        // MARK: - Codable

        enum CodingKeys: String, CodingKey {
            case localizedKey
            case action
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.localizedKey = try values.decode(String.self, forKey: .localizedKey)

            var actionName = try values.decode(String.self, forKey: .action)
            if actionName.hasSuffix(":") {
                actionName.removeLast()
            }
            self.action = NSSelectorFromString(actionName)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.localizedKey, forKey: .localizedKey)

            let actionName = NSStringFromSelector(self.action)
            try container.encode(actionName, forKey: .action)
        }
    }

    static let instance = UserActions()

    let openMenu: Action
    let createMeeting: Action
    let joinNextMeeting: Action
    let joinFromClipboard: Action
    let toggleMeetingNameVisibility: Action

    var allActions: [Action] {
        [
            self.createMeeting,
            self.joinNextMeeting,
            self.joinFromClipboard,
            self.toggleMeetingNameVisibility
        ]
    }

    // MARK: - Init

    private init() {
        self.openMenu = Action(localizedKey: "preferences_general_shortcut_open_menu", action: #selector(AppDelegate.statusMenuBarAction))
        self.createMeeting = Action(localizedKey: "status_bar_section_join_create_meeting", action: #selector(AppDelegate.createMeeting))
        self.joinNextMeeting = Action(localizedKey: "status_bar_section_join_next_meeting", action: #selector(AppDelegate.joinNextMeeting))
        self.joinFromClipboard = Action(localizedKey: "status_bar_section_join_from_clipboard", action: #selector(AppDelegate.openLinkFromClipboard))
        self.toggleMeetingNameVisibility = Action(localizedKey: "preferences_general_shortcut_toggle_meeting_name_visibility", action: #selector(AppDelegate.toggleMeetingTitleVisibility))
    }
}
