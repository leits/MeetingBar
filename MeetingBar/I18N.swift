//
//  I18N.swift
//  MeetingBar
//
//  Created by Sergey Ryazanov on 19.03.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Foundation

final class I18N {
    static let instance = I18N()

    private var bundle = Bundle.main
    var locale = Locale.current

    private init() {}

    // MARK: - App language

    @discardableResult
    func changeLanguage(to appLanguage: AppLanguage) -> Bool {
        if appLanguage == .system {
            self.resetToDefault()
            return true
        } else if let newBunlde = self.checkLanguageAvailability(appLanguage.rawValue) {
            self.bundle = newBunlde
            self.locale = Locale(identifier: appLanguage.rawValue)
            return true
        }
        self.resetToDefault()
        return false
    }

    private func resetToDefault() {
        self.bundle = Bundle.main
        self.locale = Locale.current
    }

    private func checkLanguageAvailability(_ language: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    // MARK: - Loco

    func localizedString(for key: String) -> String {
        self.bundle.localizedString(forKey: key, value: "$\(key)$", table: nil)
    }

    func localizedString(for key: String, _ arg: CVarArg) -> String {
        let format = self.localizedString(for: key)
        return String.localizedStringWithFormat(format, arg)
    }

    func localizedString(for key: String, _ firstArg: CVarArg, _ secondArg: CVarArg) -> String {
        let format = self.localizedString(for: key)
        return String.localizedStringWithFormat(format, firstArg, secondArg)
    }

    func localizedString(for key: String, _ firstArg: CVarArg, _ secondArg: CVarArg, _ thirdArg: CVarArg) -> String {
        let format = self.localizedString(for: key)
        return String.localizedStringWithFormat(format, firstArg, secondArg, thirdArg)
    }
}
