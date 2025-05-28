//
//  BaseTestCase.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import XCTest
import Defaults

class BaseTestCase: XCTestCase {

    private static let domain = Bundle.main.bundleIdentifier!
    private var snapshot: [String: Any] = [:]

    override func setUp() {
        super.setUp()

        let defaults = UserDefaults.standard

        snapshot = defaults.persistentDomain(forName: Self.domain) ?? [:]

        defaults.removePersistentDomain(forName: Self.domain)
        defaults.setVolatileDomain([:], forName: Self.domain)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard

        defaults.removeVolatileDomain(forName: Self.domain)

        defaults.setPersistentDomain(snapshot, forName: Self.domain)
        snapshot.removeAll()

        super.tearDown()
    }
}
