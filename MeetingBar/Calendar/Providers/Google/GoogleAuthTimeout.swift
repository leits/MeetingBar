//
//  GoogleAuthTimeout.swift
//  MeetingBar
//

import Foundation

struct GoogleAuthOperationTimedOut: LocalizedError {
    var errorDescription: String? {
        "Google Calendar token refresh timed out"
    }
}

/// Bridges a callback-based auth operation to async code while bounding how long
/// the caller can wait. Completion, timeout, and task cancellation race through
/// one synchronized state so the continuation is resumed exactly once.
enum GoogleAuthTimeout {
    @MainActor
    static func run<T: Sendable>(
        timeout: TimeInterval,
        operation: sending @escaping (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        precondition(timeout >= 0 && timeout.isFinite)

        let state = GoogleAuthCompletionState<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(timeout * 1_000_000_000)
                        )
                    } catch {
                        return
                    }
                    state.complete(.failure(GoogleAuthOperationTimedOut()))
                }
                state.install(timeoutTask: timeoutTask)

                operation { result in
                    state.complete(result)
                }
            }
        } onCancel: {
            state.complete(.failure(CancellationError()))
        }
    }
}

private final class GoogleAuthCompletionState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pendingResult: Result<T, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var isCompleted = false

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if isCompleted {
            let result = pendingResult
            pendingResult = nil
            lock.unlock()
            if let result {
                resume(continuation, with: result)
            }
            return
        }

        self.continuation = continuation
        lock.unlock()
    }

    func install(timeoutTask: Task<Void, Never>) {
        lock.lock()
        if isCompleted {
            lock.unlock()
            timeoutTask.cancel()
            return
        }

        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    func complete(_ result: Result<T, Error>) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }

        isCompleted = true
        let continuation = continuation
        self.continuation = nil
        let timeoutTask = timeoutTask
        self.timeoutTask = nil
        if continuation == nil {
            pendingResult = result
        }
        lock.unlock()

        timeoutTask?.cancel()
        if let continuation {
            resume(continuation, with: result)
        }
    }

    private func resume(
        _ continuation: CheckedContinuation<T, Error>,
        with result: Result<T, Error>
    ) {
        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
