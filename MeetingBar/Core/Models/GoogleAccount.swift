//
//  GoogleAccount.swift
//  MeetingBar
//
//  Created for multi-account Google Calendar support.
//  Copyright © 2026 Andrii Leitsius. All rights reserved.
//

import Defaults
import Foundation

public struct GoogleAccount: Identifiable, Codable, Hashable, Sendable, Defaults.Serializable {
    public let id: String
    public let email: String

    public init(id: String, email: String) {
        self.id = id
        self.email = email
    }
}
