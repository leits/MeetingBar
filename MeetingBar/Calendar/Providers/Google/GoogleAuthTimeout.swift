//
//  GoogleAuthTimeout.swift
//  MeetingBar
//

import Foundation

struct GoogleAuthOperationTimedOut: Error {}

/// Bounds a callback-based auth operation. AsyncThrowingStream makes callback,
/// timeout, and cancellation races safe, including callbacks that arrive late.
enum GoogleAuthTimeout {
    @MainActor
    static func run<T: Sendable>(
        timeout: TimeInterval,
        operation: sending @escaping (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        precondition(timeout >= 0 && timeout.isFinite)
        try Task.checkCancellation()

        let results = AsyncThrowingStream<T, Error> { continuation in
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return
                }
                continuation.finish(throwing: GoogleAuthOperationTimedOut())
            }
            continuation.onTermination = { _ in timeoutTask.cancel() }

            operation { result in
                switch result {
                case let .success(value):
                    continuation.yield(value)
                    continuation.finish()
                case let .failure(error):
                    continuation.finish(throwing: error)
                }
            }
        }

        for try await result in results {
            return result
        }
        throw CancellationError()
    }
}
