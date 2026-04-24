//
//  ProviderHealth.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import Foundation

public struct ProviderHealth: Equatable {
    public var lastSuccessfulRefresh: Date?
    public var lastAttemptedRefresh: Date?
    public var lastErrorDescription: String?
    /// True when the displayed data comes from a preserved snapshot, not the latest fetch attempt.
    public var isStale: Bool
    public var authRequired: Bool

    public init(
        lastSuccessfulRefresh: Date? = nil,
        lastAttemptedRefresh: Date? = nil,
        lastErrorDescription: String? = nil,
        isStale: Bool = false,
        authRequired: Bool = false
    ) {
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.lastAttemptedRefresh = lastAttemptedRefresh
        self.lastErrorDescription = lastErrorDescription
        self.isStale = isStale
        self.authRequired = authRequired
    }
}
