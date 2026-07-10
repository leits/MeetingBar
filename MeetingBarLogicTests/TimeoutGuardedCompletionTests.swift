//
//  TimeoutGuardedCompletionTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class TimeoutGuardedCompletionTests: XCTestCase {
    private struct StubError: Error {}

    func testCallbackThatNeverFiresThrowsWithinTimeoutInsteadOfHanging() async {
        let start = Date()

        do {
            _ = try await TimeoutGuardedCompletion.run(timeout: 0.05) { (completion: (Result<String, Error>) -> Void) in
                // Simulates a hung AppAuth callback: completion is never called.
                _ = completion
            }
            XCTFail("Expected OperationTimedOut")
        } catch is OperationTimedOut {
            // expected
        } catch {
            XCTFail("Expected OperationTimedOut, got \(error)")
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "must not hang past the timeout")
    }

    func testFastCallbackResolvesWithoutWaitingForTimeout() async throws {
        let start = Date()

        let value = try await TimeoutGuardedCompletion.run(timeout: 10) { (completion: (Result<String, Error>) -> Void) in
            completion(.success("token"))
        }

        XCTAssertEqual(value, "token")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "should resolve immediately, not wait for the timeout")
    }

    func testCallbackFailureIsPropagated() async {
        do {
            _ = try await TimeoutGuardedCompletion.run(timeout: 10) { (completion: (Result<String, Error>) -> Void) in
                completion(.failure(StubError()))
            }
            XCTFail("Expected StubError")
        } catch is StubError {
            // expected
        } catch {
            XCTFail("Expected StubError, got \(error)")
        }
    }

    func testLateCallbackAfterTimeoutIsIgnoredAndDoesNotCrash() async throws {
        final class LateCompletionBox: @unchecked Sendable {
            var completion: (@Sendable (Result<String, Error>) -> Void)?
        }
        let box = LateCompletionBox()

        do {
            _ = try await TimeoutGuardedCompletion.run(timeout: 0.05) { (completion: @escaping @Sendable (Result<String, Error>) -> Void) in
                box.completion = completion
            }
            XCTFail("Expected OperationTimedOut")
        } catch is OperationTimedOut {
            // expected
        }

        // The real callback fires after we've already timed out. This must not
        // crash (double-resuming a CheckedContinuation is a fatal error) or
        // otherwise have any observable effect.
        box.completion?(.success("late-token"))
    }

    func testSubsequentCallIsNotBlockedByAnEarlierHungOperation() async throws {
        do {
            _ = try await TimeoutGuardedCompletion.run(timeout: 0.05) { (completion: (Result<String, Error>) -> Void) in
                // never calls back — simulates the wedged refresh
                _ = completion
            }
            XCTFail("Expected OperationTimedOut")
        } catch is OperationTimedOut {
            // expected
        }

        let start = Date()
        let value = try await TimeoutGuardedCompletion.run(timeout: 10) { (completion: (Result<String, Error>) -> Void) in
            completion(.success("fresh-token"))
        }

        XCTAssertEqual(value, "fresh-token")
        XCTAssertLessThan(
            Date().timeIntervalSince(start),
            1.0,
            "a later call must not be blocked by the earlier hung operation"
        )
    }
}
