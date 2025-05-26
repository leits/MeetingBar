//
//  Keychain.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 19.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Security
import Foundation

enum Keychain {
    // MARK: - Public helpers
    @discardableResult
    static func save(data: Data, for service: String) -> Bool {
        delete(for: service)                                     // overwrite if exists

        let query: [String: Any] = [
            kSecClass              as String: kSecClassGenericPassword,
            kSecAttrService        as String: service,
            kSecValueData          as String: data,
            kSecAttrAccessible     as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(for service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass               as String: kSecClassGenericPassword,
            kSecAttrService         as String: service,
            kSecReturnData          as String: true,
            kSecMatchLimit          as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    @discardableResult
    static func delete(for service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass        as String: kSecClassGenericPassword,
            kSecAttrService  as String: service
        ]

        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
