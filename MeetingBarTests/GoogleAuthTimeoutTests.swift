//
//  GoogleAuthTimeoutTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class GoogleAuthTimeoutTests: XCTestCase {
    private struct StubError: Error {}

    func testCallbackThatNeverFiresTimesOut() async {
        do {
            _ = try await GoogleAuthTimeout.run(timeout: 0.02) { _ in } as String
            XCTFail("Expected GoogleAuthOperationTimedOut")
        } catch is GoogleAuthOperationTimedOut {
            // Expected.
        } catch {
            XCTFail("Expected GoogleAuthOperationTimedOut, got \(error)")
        }
    }

    func testFastCallbackWinsWhenTimeoutTaskIsCancelled() async throws {
        for _ in 0..<100 {
            let value = try await GoogleAuthTimeout.run(timeout: 10) { completion in
                completion(.success("token"))
            }
            XCTAssertEqual(value, "token")
        }
    }

    func testCallbackFailureIsPropagated() async {
        do {
            _ = try await GoogleAuthTimeout.run(timeout: 10) { completion in
                completion(.failure(StubError()))
            } as String
            XCTFail("Expected StubError")
        } catch is StubError {
            // Expected.
        } catch {
            XCTFail("Expected StubError, got \(error)")
        }
    }

    func testLateCallbackDoesNotAffectTheNextCall() async {
        final class CompletionBox: @unchecked Sendable {
            var completion: (@Sendable (Result<String, Error>) -> Void)?
        }
        let box = CompletionBox()

        do {
            _ = try await GoogleAuthTimeout.run(timeout: 0.02) { completion in
                box.completion = completion
            }
            XCTFail("Expected GoogleAuthOperationTimedOut")
        } catch is GoogleAuthOperationTimedOut {
            // Expected.
        } catch {
            XCTFail("Expected GoogleAuthOperationTimedOut, got \(error)")
        }

        box.completion?(.success("late-token"))

        let value = try? await GoogleAuthTimeout.run(timeout: 10) { completion in
            completion(.success("fresh-token"))
        }
        XCTAssertEqual(value, "fresh-token")
    }

    func testCancellationFinishesWithoutWaitingForTimeout() async {
        let task = Task<String, Error> {
            try await GoogleAuthTimeout.run(timeout: 10) { _ in }
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}
