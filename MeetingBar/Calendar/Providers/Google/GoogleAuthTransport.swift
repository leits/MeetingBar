//
//  GoogleAuthTransport.swift
//  MeetingBar
//

import AppAuthCore
import Foundation

/// Owns the URLSession used internally by AppAuth. Rotating the session cancels
/// an underlying token request that AppAuth otherwise does not expose.
@MainActor
final class GoogleAuthTransport {
    private var session: URLSession

    init() {
        let session = Self.makeSession()
        self.session = session
        OIDURLSessionProvider.setSession(session)
    }

    func reset() {
        let previousSession = session
        let replacementSession = Self.makeSession()
        session = replacementSession
        OIDURLSessionProvider.setSession(replacementSession)
        previousSession.invalidateAndCancel()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }
}
