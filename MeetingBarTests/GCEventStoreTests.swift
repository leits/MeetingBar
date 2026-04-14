//
//  GCEventStoreTests.swift
//  MeetingBarTests
//
//  Created by Codex on 14.04.2026.
//

import AppAuthCore
@testable import MeetingBar
import XCTest

final class GCEventStoreTests: XCTestCase {
    @MainActor
    func testEnsureSignedInAndSignOutPathsWithoutNetwork() async throws {
        let store = GCEventStore.shared
        let originalState = store._test_getAuthState()
        defer { store._test_setAuthState(originalState) }

        // refreshToken is nil while isAuthorized is true
        // this should execute the force-consent branch without launching OAuth UI.
        let noRefreshState = try makeAuthState(refreshToken: nil)
        store._test_setAuthState(noRefreshState)
        try await store._test_ensureSignedIn()

        // refreshToken exists and should return from ensureSignedIn guard.
        let validSessionState = try makeAuthState(refreshToken: "refresh-token-1")
        store._test_setAuthState(validSessionState)
        try await store._test_ensureSignedIn()

        // signOut should execute token extraction path, but avoid revoke calls when tokens are absent.
        store._test_setAuthState(makeAuthorizationOnlyState())
        await store.signOut()
    }

    func testRefreshTokenChecksUseAuthStateRefreshToken() throws {
        let authState = try makeAuthState()

        // Simulate a refresh response that omits refresh_token (Google behavior).
        let refreshRequest = try XCTUnwrap(authState.tokenRefreshRequest())
        let refreshedTokenResponse = OIDTokenResponse(
            request: refreshRequest,
            parameters: tokenParameters(accessToken: "access-token-2", refreshToken: nil)
        )
        authState.update(with: refreshedTokenResponse, error: nil)

        XCTAssertEqual(authState.refreshToken, "refresh-token-1")
        XCTAssertNil(authState.lastTokenResponse?.refreshToken)

        XCTAssertEqual(GCEventStore.refreshToken(in: authState), "refresh-token-1")
        XCTAssertTrue(GCEventStore.hasAuthorizedSession(authState))
        XCTAssertFalse(GCEventStore.shouldForceConsent(authState))
    }

    func testConsentAndSessionChecksWithoutRefreshToken() throws {
        let authState = try makeAuthState(refreshToken: nil)

        XCTAssertNil(authState.refreshToken)
        XCTAssertNil(GCEventStore.refreshToken(in: authState))
        XCTAssertFalse(GCEventStore.hasAuthorizedSession(authState))
        XCTAssertTrue(GCEventStore.shouldForceConsent(authState))
    }

    private func makeAuthState(refreshToken: String? = "refresh-token-1") throws -> OIDAuthState {
        let serviceConfiguration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
        let request = OIDAuthorizationRequest(
            configuration: serviceConfiguration,
            clientId: "client-id",
            clientSecret: nil,
            scopes: ["email"],
            redirectURL: URL(string: "com.test.app:/oauthredirect")!,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
        let response = OIDAuthorizationResponse(
            request: request,
            parameters: [
                "code": "authorization-code" as NSString
            ]
        )
        let tokenRequest = try XCTUnwrap(response.tokenExchangeRequest())

        let tokenParameters = tokenParameters(accessToken: "access-token-1", refreshToken: refreshToken)

        let tokenResponse = OIDTokenResponse(request: tokenRequest, parameters: tokenParameters)
        return OIDAuthState(authorizationResponse: response, tokenResponse: tokenResponse)
    }

    private func tokenParameters(accessToken: String, refreshToken: String?) -> [String: NSObject & NSCopying] {
        var parameters: [String: NSObject & NSCopying] = [
            "access_token": "access-token-1" as NSString,
            "token_type": "Bearer" as NSString,
            "expires_in": 3600 as NSNumber
        ]
        if let refreshToken {
            parameters["refresh_token"] = refreshToken as NSString
        }
        parameters["access_token"] = accessToken as NSString
        return parameters
    }

    private func makeAuthorizationOnlyState() -> OIDAuthState {
        let request = authorizationRequest()
        let response = OIDAuthorizationResponse(
            request: request,
            parameters: [
                "code": "authorization-code" as NSString
            ]
        )
        return OIDAuthState(authorizationResponse: response)
    }

    private func authorizationRequest() -> OIDAuthorizationRequest {
        let serviceConfiguration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
        return OIDAuthorizationRequest(
            configuration: serviceConfiguration,
            clientId: "client-id",
            clientSecret: nil,
            scopes: ["email"],
            redirectURL: URL(string: "com.test.app:/oauthredirect")!,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
    }
}
