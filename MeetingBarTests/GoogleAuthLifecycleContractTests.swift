import AppAuthCore
import Foundation
import XCTest

@testable import MeetingBar

@MainActor
final class GoogleAuthLifecycleContractTests: XCTestCase {
    func testRefreshCallbackSuccessReturnsNewToken() throws {
        XCTAssertEqual(
            try GCEventStore.resolveTokenRefresh(accessToken: "new-token", error: nil),
            "new-token"
        )
    }

    func testNetworkErrorWinsOverStaleToken() {
        let error = URLError(.notConnectedToInternet)
        do {
            _ = try GCEventStore.resolveTokenRefresh(
                accessToken: "stale-access-token", error: error
            )
            XCTFail("Never reuse the old token when the refresh endpoint failed")
        } catch {
            guard case let AuthError.temporarilyUnavailable(underlying) = error else {
                return XCTFail("Expected transient auth error, got \(error)")
            }
            XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testExplicitOAuthTokenRejectionRequiresReauthorization() {
        let invalidGrant = NSError(domain: OIDOAuthTokenErrorDomain, code: 400)
        do {
            _ = try GCEventStore.resolveTokenRefresh(
                accessToken: "previous-access-token",
                error: invalidGrant
            )
            XCTFail("Invalid refresh grant cannot be treated as a successful access token")
        } catch {
            guard case AuthError.notSignedIn = error else {
                return XCTFail("Expected reauthorization, got \(error)")
            }
        }
    }

    func testNoTokenAndNoErrorReturnsExplicitFailure() {
        do {
            _ = try GCEventStore.resolveTokenRefresh(accessToken: nil, error: nil)
            XCTFail("Missing access token cannot become a successful empty response")
        } catch {
            guard case AuthError.refreshFailed = error else {
                return XCTFail("Expected refresh failure, got \(error)")
            }
        }
    }

    func testNewAuthorizationCompletesOldWaiterAndKeepsNewOneAlive() {
        let slot = GoogleAuthorizationFlowSlot()
        let firstGeneration = slot.begin()
        var firstCompleted = 0
        var firstCancelled = false
        slot.register(firstGeneration) { result in
            firstCompleted += 1
            if case .failure(AuthError.cancelled) = result { firstCancelled = true }
        }

        let secondGeneration = slot.begin()
        XCTAssertTrue(firstCancelled)
        XCTAssertEqual(firstCompleted, 1)
        XCTAssertFalse(slot.isPending(firstGeneration))

        var secondCompleted = 0
        slot.register(secondGeneration) { result in
            if case .success = result { secondCompleted += 1 }
        }
        slot.finish(firstGeneration, result: .success(()))
        XCTAssertTrue(slot.isPending(secondGeneration))
        XCTAssertEqual(secondCompleted, 0)
        slot.finish(secondGeneration, result: .success(()))
        slot.finish(secondGeneration, result: .success(()))
        XCTAssertEqual(secondCompleted, 1)
        XCTAssertEqual(firstCompleted, 1)
    }

    func testCancellingCurrentAuthorizationSettlesAwaiterWithoutAppAuthCallback() {
        let slot = GoogleAuthorizationFlowSlot()
        let attempt = slot.begin()
        var cancellations = 0
        slot.register(attempt) { result in
            if case .failure(AuthError.cancelled) = result { cancellations += 1 }
        }
        slot.cancel()
        slot.finish(attempt, result: .success(()))
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(slot.isPending(attempt))
    }

    func testLateAuthorizationCallbackCannotInstallStaleSession() {
        var installedState: String?
        XCTAssertThrowsError(try GCEventStore.acceptAuthorizationResult(
            issuedGeneration: 4,
            currentGeneration: 5,
            state: "obsolete-oauth-state",
            error: nil,
            install: { installedState = $0 }
        )) { error in
            guard case AuthError.cancelled = error else {
                return XCTFail("Expected cancelled flow; got \(error)")
            }
        }
        XCTAssertNil(installedState)
    }

    func testCurrentAuthorizationCallbackInstallsSessionExactlyOnce() throws {
        var installed: [String] = []
        try GCEventStore.acceptAuthorizationResult(
            issuedGeneration: 5,
            currentGeneration: 5,
            state: "new-oauth-state",
            error: nil,
            install: { installed.append($0) }
        )
        XCTAssertEqual(installed, ["new-oauth-state"])
    }

    func testMissingSessionCannotSkipSignInEvenWithoutForcedPrompt() {
        XCTAssertFalse(GCEventStore.shouldSkipSignIn(forcePrompt: false, state: nil))
        XCTAssertFalse(GCEventStore.shouldSkipSignIn(forcePrompt: true, state: nil))
    }
}

@MainActor
final class GoogleSignOutConcurrencyTests: XCTestCase {
    func testLateRevocationCannotClearNewlyAuthorizedSession() async {
        let gate = TokenRevocationGate()
        var activeSession: String? = "original-auth-state"
        let oldAccessToken = "old-access"
        let oldRefreshToken = "old-refresh"

        let oldSignOut = Task {
            await GCEventStore.revokeTokensAfterClearingSession(
                accessToken: oldAccessToken,
                refreshToken: oldRefreshToken,
                clearSession: { activeSession = nil },
                revoke: { token in await gate.revoke(token: token) }
            )
        }
        await gate.waitForCount(2)
        XCTAssertNil(activeSession, "Sign-out must clear the old session before revocation suspends")

        // A newer Google selection obtains a distinct state while the old
        // network revocations are still waiting to finish.
        activeSession = "new-auth-state"
        await gate.finish()
        await oldSignOut.value

        XCTAssertEqual(activeSession, "new-auth-state")
        let revoked = await gate.revokedTokens
        XCTAssertEqual(Set(revoked), [oldAccessToken, oldRefreshToken])
    }
}

private actor TokenRevocationGate {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var revokedTokens: [String] = []

    func revoke(token: String) async {
        revokedTokens.append(token)
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            if pending.count == 2 {
                waiters.forEach { $0.resume() }
                waiters.removeAll()
            }
        }
    }

    func waitForCount(_ count: Int) async {
        guard pending.count < count else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish() {
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume() }
    }
}
