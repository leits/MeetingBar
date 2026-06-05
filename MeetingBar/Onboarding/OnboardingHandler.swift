//
//  OnboardingHandler.swift
//  MeetingBar
//
//  Holds the app-level callback that AccessScreen invokes when the user
//  selects and authorises a calendar provider.  Injected as an
//  EnvironmentObject so no view needs to reach into AppDelegate directly.
//

import Foundation

/// Observable wrapper around the single onboarding completion callback.
///
/// AppDelegate creates one instance, stores the completion logic in it, and
/// injects it into `OnboardingView` via `.environmentObject(handler)`.
/// After `onProviderSelected` resolves, AppDelegate sets `appModel` so
/// `CalendarsScreen` can observe it without reaching back into AppDelegate.
@MainActor
final class OnboardingHandler: ObservableObject {
    /// Called when the user successfully authorises a calendar provider.
    var onProviderSelected:
        @MainActor (EventStoreProvider) async -> ProviderSelectionResult

    /// Set by AppDelegate after `setup()` completes during onboarding.
    /// `CalendarsScreen` observes this to obtain the live `AppModel`.
    @Published var appModel: AppModel?

    init(
        onProviderSelected:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult
    ) {
        self.onProviderSelected = onProviderSelected
    }
}
