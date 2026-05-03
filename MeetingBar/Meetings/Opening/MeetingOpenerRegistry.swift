//
//  MeetingOpenerRegistry.swift
//  MeetingBar
//
//  Maps each MeetingServices case to its MeetingOpenStrategy.
//  openMeetingURL() delegates here instead of using a large switch.
//

import Defaults
import Foundation

enum MeetingOpenerRegistry {
    /// Returns the open strategy for the given service (or the default browser
    /// strategy when the service is nil or has no custom strategy).
    static func strategy(for service: MeetingServices?) -> any MeetingOpenStrategy {
        guard let service else {
            return DefaultBrowserOpenStrategy()
        }
        return strategies[service] ?? DefaultBrowserOpenStrategy()
    }

    // MARK: - Private map

    private nonisolated(unsafe) static let strategies: [MeetingServices: any MeetingOpenStrategy] =
        [
            // Google Meet
            .meet: MeetInOneOpenStrategy(),
            .meetStream: MeetInOneOpenStrategy(),

            // Zoom web URL → app scheme
            .zoom: ZoomWebOpenStrategy(),
            .zoomgov: ZoomWebOpenStrategy(),

            // Zoom native app scheme → browser fallback
            .zoom_native: ZoomNativeOpenStrategy(),

            // Microsoft Teams
            .teams: TeamsOpenStrategy(),

            // Jitsi
            .jitsi: JitsiOpenStrategy(),

            // Slack huddle
            .slack: SlackHuddleOpenStrategy(),

            // Riverside
            .riverside: RiversideOpenStrategy(),

            // FaceTime
            .facetime: NativeSchemeOpenStrategy(schemePrefix: "facetime://"),
            .facetimeaudio: NativeSchemeOpenStrategy(schemePrefix: "facetime-audio://"),

            // Phone
            .phone: NativeSchemeOpenStrategy(schemePrefix: "tel://"),

            // Providers with per-provider browser preferences (default browser key
            // is nil here — the per-provider key is read inside DefaultBrowserOpenStrategy
            // once WritableKeyPath support is added; for now they fall through to default).
        ]
}
