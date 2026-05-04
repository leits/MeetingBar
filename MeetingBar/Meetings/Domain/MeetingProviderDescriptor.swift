//
//  MeetingProviderDescriptor.swift
//  MeetingBar
//
//  Value-type description of one meeting provider.
//  No AppKit or Defaults imports — pure domain data.
//

/// Centralises all per-provider metadata that was previously scattered across
/// independent switch statements in `MeetingServices.swift` and
/// `MeetingLinkDetection.swift`.
///
/// The `id` is a stable string identity. For built-in providers it equals the
/// `rawValue` of the corresponding `MeetingServices` case.
struct MeetingProviderDescriptor: Equatable, Sendable {
    /// Stable string identity. For built-in providers this equals `MeetingServices.rawValue`.
    let id: String

    /// Human-readable display name.
    let displayName: String

    /// `NSImage(named:)` key for the provider icon.
    /// System template image names (e.g. "NSTouchBarOpenInBrowserTemplate") are valid here.
    let iconName: String

    /// Rendered icon width in points. Almost always 16.
    let iconWidth: Double

    /// Rendered icon height in points. Varies by provider logo aspect ratio.
    let iconHeight: Double

    /// URL detection regex pattern. `nil` for providers that don't use URL matching
    /// (e.g. phone, facetimeaudio, url catch-all, other).
    let regexPattern: String?

    /// Name of the per-provider native-app "browser" sentinel that appears in the
    /// browser picker for this provider.  `nil` means only real browsers are shown.
    /// This is a plain String so the descriptor stays free of AppKit / Defaults imports.
    let nativeAppBrowserName: String?
}
