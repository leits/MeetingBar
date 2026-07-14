//
//  GoogleCalendarPolicy.swift
//  MeetingBar
//

import Foundation

enum AuthError: LocalizedError {
    case cancelled
    case notSignedIn
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Google Calendar authorization was cancelled"
        case .notSignedIn:
            return "Google Calendar authorization is required"
        case .refreshFailed:
            return "Google Calendar token refresh failed"
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

/// Thrown by `TimeoutGuardedCompletion.run` when `operation` doesn't call back in time.
struct OperationTimedOut: Error {}

/// Runs a completion-callback-based `operation`, racing it against a hard timeout so a
/// callback that never fires (e.g. AppAuth's token refresh parked across sleep/wake)
/// can't wedge the awaiting call forever. Whichever of the real callback or the timeout
/// fires first wins; the other is a no-op, so `operation`'s completion is safe to invoke
/// late without double-resuming the caller.
enum TimeoutGuardedCompletion {
    static func run<T: Sendable>(
        timeout: TimeInterval,
        operation: sending @escaping (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let resumer = SingleResume(continuation)

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                resumer.resume(with: .failure(OperationTimedOut()))
            }

            operation { result in
                timeoutTask.cancel()
                resumer.resume(with: result)
            }
        }
    }
}

/// Resumes a `CheckedContinuation` at most once, even when the real completion and the
/// timeout race to resume it concurrently.
private final class SingleResume<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()

        guard let pending else { return }
        switch result {
        case let .success(value): pending.resume(returning: value)
        case let .failure(error): pending.resume(throwing: error)
        }
    }
}
