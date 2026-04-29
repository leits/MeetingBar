//
//  DiagnosticsReport+MeetingBar.swift
//  MeetingBar
//

import Foundation

extension DiagnosticsProvider {
    init(provider: EventStoreProvider) {
        switch provider {
        case .macOSEventKit:
            self = .macOSEventKit
        case .googleCalendar:
            self = .googleCalendar
        }
    }
}

extension DiagnosticsHealth {
    init(health: ProviderHealth) {
        self.init(
            lastSuccessfulRefresh: health.lastSuccessfulRefresh,
            lastAttemptedRefresh: health.lastAttemptedRefresh,
            lastErrorDescription: health.lastErrorDescription,
            isStale: health.isStale,
            authRequired: health.authRequired
        )
    }
}

extension DiagnosticsContext {
    init(
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        provider: EventStoreProvider,
        selectedCalendarCount: Int,
        totalCalendarCount: Int,
        visibleEventCount: Int,
        health: ProviderHealth
    ) {
        self.init(
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            provider: DiagnosticsProvider(provider: provider),
            selectedCalendarCount: selectedCalendarCount,
            totalCalendarCount: totalCalendarCount,
            visibleEventCount: visibleEventCount,
            health: DiagnosticsHealth(health: health)
        )
    }
}
