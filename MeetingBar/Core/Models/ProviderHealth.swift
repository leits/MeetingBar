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

extension ProviderHealth {
    static func success(attempted: Date) -> ProviderHealth {
        ProviderHealth(
            lastSuccessfulRefresh: attempted,
            lastAttemptedRefresh: attempted,
            lastErrorDescription: nil,
            isStale: false,
            authRequired: false
        )
    }

    static func failure(
        previous: ProviderHealth,
        attempted: Date,
        error: Error
    ) -> ProviderHealth {
        ProviderHealth(
            lastSuccessfulRefresh: previous.lastSuccessfulRefresh,
            lastAttemptedRefresh: attempted,
            lastErrorDescription: Self.errorDescription(error),
            isStale: true,
            authRequired: Self.isAuthRequired(error)
        )
    }

    private static func errorDescription(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return error.localizedDescription
    }

    private static func isAuthRequired(_ error: Error) -> Bool {
        if let authError = error as? AuthError {
            switch authError {
            case .notSignedIn, .refreshFailed:
                return true
            }
        }

        switch error {
        case let EventManagerError.calendarAccessFailed(underlying):
            return isAuthRequired(underlying)
        case let EventManagerError.eventFetchFailed(underlying):
            return isAuthRequired(underlying)
        default:
            return false
        }
    }
}
