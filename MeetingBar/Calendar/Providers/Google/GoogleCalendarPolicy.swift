//
//  GoogleCalendarPolicy.swift
//  MeetingBar
//

import Foundation

/// Arbitrates a single resume between two racing callbacks.
///
/// A continuation must be resumed exactly once. When a wait is settled by
/// whichever of two independent callbacks arrives first — a library completion
/// handler and a timeout — the loser has to know to stay silent, and neither
/// side can assume which one that is. `claim()` returns `true` to the first
/// caller and `false` to every caller after it.
final class SingleResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    /// `true` for the first caller only; every later caller gets `false`.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isClaimed { return false }
        isClaimed = true
        return true
    }
}

enum AuthError: LocalizedError {
    case cancelled
    case notSignedIn
    case refreshFailed
    /// The token endpoint could not be reached (offline, VPN still connecting,
    /// captive portal). The stored refresh token is still presumed valid, so
    /// callers must retry later rather than signing the user out.
    case temporarilyUnavailable(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Google Calendar authorization was cancelled"
        case .notSignedIn:
            return "Google Calendar authorization is required"
        case .refreshFailed:
            return "Google Calendar token refresh failed"
        case let .temporarilyUnavailable(underlying):
            return "Google Calendar is temporarily unreachable: \(underlying.localizedDescription)"
        }
    }
}

enum GoogleCalendarError: LocalizedError, Equatable {
    case unauthorized(URL)
    case forbiddenCalendar(calendarID: String?, url: URL)
    case httpStatus(Int, url: URL)
    case missingItems(URL)

    var errorDescription: String? {
        switch self {
        case let .unauthorized(url):
            return "Google Calendar authorization failed: \(url.absoluteString)"
        case let .forbiddenCalendar(calendarID, url):
            if let calendarID {
                return "Google Calendar is not accessible: \(calendarID)"
            }
            return "Google Calendar access is forbidden: \(url.absoluteString)"
        case let .httpStatus(statusCode, url):
            return "Google Calendar request failed with HTTP \(statusCode): \(url.absoluteString)"
        case let .missingItems(url):
            return "Google Calendar response did not contain an items array: \(url.absoluteString)"
        }
    }
}

enum GoogleHTTPDecision: Equatable {
    case proceed
    case retryWithForcedTokenRefresh
    /// Surface "reconnect required" to the user without discarding the stored
    /// session. A 401 from the Calendar API only proves the *access* token was
    /// rejected; it says nothing about the refresh token, and a proxy or
    /// captive portal can produce one while the grant is perfectly valid.
    /// Only the token endpoint rejecting the refresh token (which AppAuth
    /// reports through `didEncounterAuthorizationError`) may clear the session.
    case throwAuthRequired
    case throwError(GoogleCalendarError)
}

enum GoogleHTTPStatusPolicy {
    static func classify(
        statusCode: Int,
        url: URL,
        calendarID: String?,
        retrying: Bool
    ) -> GoogleHTTPDecision {
        switch statusCode {
        case 200...299:
            return .proceed
        case 401:
            return retrying ? .throwAuthRequired : .retryWithForcedTokenRefresh
        case 403:
            return retrying
                ? .throwError(.forbiddenCalendar(calendarID: calendarID, url: url))
                : .retryWithForcedTokenRefresh
        default:
            return .throwError(.httpStatus(statusCode, url: url))
        }
    }
}

enum GoogleCalendarBatchPolicy {
    static func finish<Event>(
        events: [Event],
        successfulCalendars: Int,
        forbiddenErrors: [Error]
    ) throws -> [Event] {
        if successfulCalendars == 0, let error = forbiddenErrors.first {
            throw error
        }
        return events
    }
}
