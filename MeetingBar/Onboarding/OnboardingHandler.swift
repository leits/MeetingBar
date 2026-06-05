//
//  OnboardingHandler.swift
//  MeetingBar
//
//  Holds the app-level callback that AccessScreen invokes when the user
//  selects and authorises a calendar provider.  Injected as an
//  EnvironmentObject so no view needs to reach into AppDelegate directly.
//

import Foundation

/// Observable wrapper around onboarding application workflows.
///
/// AppDelegate creates one instance, stores the completion logic in it, and
/// injects it into `OnboardingView` via `.environmentObject(handler)`.
@MainActor
final class OnboardingHandler: ObservableObject {
    var onProviderSelected:
        @MainActor (EventStoreProvider) async -> ProviderSelectionResult
    var onComplete:
        @MainActor (EventStoreProvider) async -> ProviderSelectionResult

    @Published var appModel: AppModel?

    init(
        onProviderSelected:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult,
        onComplete:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult
    ) {
        self.onProviderSelected = onProviderSelected
        self.onComplete = onComplete
    }
}
