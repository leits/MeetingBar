//
//  AppRuntimeBridge.swift
//  MeetingBar
//

import Foundation

/// Narrow bridge for system-created entry points that cannot receive normal
/// dependencies, such as AppIntents.
///
/// This is not business state. AppDelegate installs the live AppModel once the
/// app is composed, and external entry points forward value actions here.
@MainActor
final class AppRuntimeBridge {
    static let shared = AppRuntimeBridge()

    private weak var appModel: AppModel?
    private var onboardingPresenter: (() -> Void)?

    private init() {}

    func install(appModel: AppModel) {
        self.appModel = appModel
    }

    /// AppDelegate registers how to (re)open the first-run setup window so debug
    /// entry points can trigger it without reaching into AppKit directly.
    func installOnboardingPresenter(_ presenter: @escaping () -> Void) {
        onboardingPresenter = presenter
    }

    func openOnboarding() {
        onboardingPresenter?()
    }

    func nearestEvent() -> MBEvent? {
        appModel?.nextEvent()
    }

    func send(_ action: AppAction) {
        appModel?.send(action)
    }
}
