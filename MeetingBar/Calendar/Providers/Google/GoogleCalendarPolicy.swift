//
//  GoogleCalendarPolicy.swift
//  MeetingBar
//

import Foundation

enum AuthError: LocalizedError {
    case cancelled
    case notSignedIn
    case refreshFailed
    case refreshTimedOut

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Google Calendar authorization was cancelled"
        case .notSignedIn:
            return "Google Calendar authorization is required"
        case .refreshFailed:
            return "Google Calendar token refresh failed"
        case .refreshTimedOut:
            return "Google Calendar token refresh timed out"
        }
    }
}

enum GoogleAuthErrorPolicy {
    static func isNetworkTimeout(_ error: Error) -> Bool {
        var current: NSError? = error as NSError

        // AppAuth wraps URLSession failures in OIDGeneralErrorDomain and keeps
        // the original URLError under NSUnderlyingErrorKey.
        for _ in 0..<8 {
            guard let candidate = current else { return false }
            if candidate.domain == NSURLErrorDomain,
               candidate.code == URLError.timedOut.rawValue {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return false
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
    case clearAuthAndThrowAuthRequired
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
            return retrying ? .clearAuthAndThrowAuthRequired : .retryWithForcedTokenRefresh
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
