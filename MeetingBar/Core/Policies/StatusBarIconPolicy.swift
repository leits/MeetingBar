//
//  StatusBarIconPolicy.swift
//  MeetingBar
//

import Foundation

/// Shadow of `EventTitleIconFormat` so the policy stays hostless. The
/// `+MeetingBar.swift` adapter converts from the production Defaults enum.
enum StatusBarIconFormat: Equatable {
    case calendar
    case appicon
    case eventtype
    case none
}

/// What the status bar should render as its icon.
///
/// `asset(name)` is loaded via `NSImage(named:)` by the renderer; the renderer
/// is expected to fall back to a safe placeholder when the asset is missing
/// (see `MenuStyleConstants.iconNamed(_:)`).
enum StatusBarIcon: Equatable {
    case asset(String)
    case meetingService(MeetingServices?)
    case none
}

/// Asset names the renderer needs. Passed in by the caller so the policy is
/// fully decoupled from `MenuStyleConstants` and easy to test.
struct StatusBarIconAssets: Equatable {
    let appIcon: String
    let calendarCheckmark: String
    let calendar: String
}

/// Picks the status bar icon based on the current title mode, the user's
/// chosen icon format, and (for `.eventtype` format on a real event) the
/// next event's meeting service.
///
/// Decision matrix:
///
/// | mode             | format                      | icon                |
/// | ---------------- | --------------------------- | ------------------- |
/// | idle             | (any)                       | app icon            |
/// | noUpcoming       | appicon                     | app icon            |
/// | noUpcoming       | calendar / eventtype / none | calendar-checkmark  |
/// | afterThreshold   | appicon                     | app icon            |
/// | afterThreshold   | calendar / eventtype / none | calendar            |
/// | nextEvent        | none                        | no icon             |
/// | nextEvent        | eventtype                   | meetingService(...) |
/// | nextEvent        | appicon / calendar          | named asset         |
enum StatusBarIconPolicy {
    static func icon(
        mode: StatusBarTitleMode,
        format: StatusBarIconFormat,
        formatAssetName: String,
        meetingService: MeetingServices?,
        assets: StatusBarIconAssets
    ) -> StatusBarIcon {
        switch mode {
        case .idle:
            return .asset(assets.appIcon)
        case .noUpcoming:
            return format == .appicon
                ? .asset(assets.appIcon)
                : .asset(assets.calendarCheckmark)
        case .afterThreshold:
            return format == .appicon
                ? .asset(assets.appIcon)
                : .asset(assets.calendar)
        case .nextEvent:
            switch format {
            case .none:
                return .none
            case .eventtype:
                return .meetingService(meetingService)
            case .appicon, .calendar:
                return .asset(formatAssetName)
            }
        }
    }
}
