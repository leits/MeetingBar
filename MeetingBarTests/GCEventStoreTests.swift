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
    func testRefreshTokenChecksUseAuthStateRefreshToken() throws {
        let authState = try makeAuthState()

        // Simulate a refresh response that omits refresh_token (Google behavior).
        let refreshRequest = try XCTUnwrap(authState.tokenRefreshRequest())
        let refreshedTokenResponse = OIDTokenResponse(
            request: refreshRequest,
            parameters: [
                "access_token": "access-token-2",
                "token_type": "Bearer",
                "expires_in": 3600
            ]
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
                "code": "authorization-code"
            ]
        )
        let tokenRequest = try XCTUnwrap(response.tokenExchangeRequest())

        var tokenParameters: [String: NSObject & NSCopying] = [
            "access_token": "access-token-1" as NSString,
            "token_type": "Bearer" as NSString,
            "expires_in": 3600 as NSNumber
        ]
        if let refreshToken {
            tokenParameters["refresh_token"] = refreshToken as NSString
        }

        let tokenResponse = OIDTokenResponse(request: tokenRequest, parameters: tokenParameters)
        return OIDAuthState(authorizationResponse: response, tokenResponse: tokenResponse)
    }
}
