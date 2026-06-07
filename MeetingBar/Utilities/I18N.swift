//
//  I18N.swift
//  MeetingBar
//
//  Created by Sergey Ryazanov on 19.03.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Foundation

final class I18N {
    nonisolated(unsafe) static let instance = I18N()

    private var bundle: Bundle
    var locale: Locale
    private let englishBundle: Bundle

    private init() {
        bundle = Bundle.main
        locale = Locale.current
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let englishBundle = Bundle(path: path) {
            self.englishBundle = englishBundle
        } else {
            englishBundle = Bundle.main
        }
    }

    init(bundle: Bundle, englishBundle: Bundle, locale: Locale = .current) {
        self.bundle = bundle
        self.englishBundle = englishBundle
        self.locale = locale
    }

    // MARK: - App language

    @discardableResult
    func changeLanguage(to appLanguage: AppLanguage) -> Bool {
        if appLanguage == .system {
            resetToDefault()
            return true
        } else if let newBundle = checkLanguageAvailability(appLanguage.rawValue) {
            bundle = newBundle
            locale = Locale(identifier: appLanguage.rawValue)
            return true
        }
        resetToDefault()
        return false
    }

    private func resetToDefault() {
        bundle = Bundle.main
        locale = Locale.current
    }

    private func checkLanguageAvailability(_ language: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    // MARK: - Loco

    func localizedString(for key: String) -> String {
        let missingMarker = "$\(key)$"
        let localized = bundle.localizedString(forKey: key, value: missingMarker, table: nil)
        if localized == key || localized == missingMarker {
            return englishBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return localized
    }

    func localizedString(for key: String, _ arg: CVarArg) -> String {
        let format = localizedString(for: key)
        return String.localizedStringWithFormat(format, arg)
    }

    func localizedString(for key: String, _ firstArg: CVarArg, _ secondArg: CVarArg) -> String {
        let format = localizedString(for: key)
        return String.localizedStringWithFormat(format, firstArg, secondArg)
    }

    func localizedString(for key: String, _ firstArg: CVarArg, _ secondArg: CVarArg, _ thirdArg: CVarArg) -> String {
        let format = localizedString(for: key)
        return String.localizedStringWithFormat(format, firstArg, secondArg, thirdArg)
    }
}
