import AppAuthCore
import Foundation
import XCTest

@testable import MeetingBar

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

    func testMissingSessionCannotSkipSignInEvenWithoutForcedPrompt() {
        XCTAssertFalse(GCEventStore.shouldSkipSignIn(forcePrompt: false, state: nil))
        XCTAssertFalse(GCEventStore.shouldSkipSignIn(forcePrompt: true, state: nil))
    }
}
