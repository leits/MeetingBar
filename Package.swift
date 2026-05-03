// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MeetingBarLogic",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "MeetingBarLogic", targets: ["MeetingBarLogic"])
    ],
    targets: [
        .target(
            name: "MeetingBarLogic",
            path: "MeetingBar",
            exclude: [
                // Exclude app-layer files that depend on AppKit/Defaults/EventKit.
                // SPM scans the whole MeetingBar/ tree for resources; these paths
                // prevent it from picking up .lproj bundles and asset catalogues.
                "Resources ",
                "Assets.xcassets",
                "Base.lproj",
                "Preview Content",
            ],
            sources: [
                // Core/Policies — pure hostless logic.
                // Add paths here when pure files move out of Core/Policies in later phases.
                "Core/Policies/DiagnosticsReport.swift",
                "Core/Policies/EventActionPolicy.swift",
                "Core/Policies/EventFilterPolicy.swift",
                "Core/Policies/EventSelectionPolicy.swift",
                "Core/Policies/GoogleCalendarPolicy.swift",
                "Core/Policies/MeetingLinkCandidate.swift",
                "Core/Policies/MeetingLinkDetection.swift",
                "Core/Policies/MeetingLinkDetector.swift",
                "Core/Policies/MeetingOpeningPolicy.swift",
                "Core/Policies/NotificationPlanningPolicy.swift",
                "Core/Policies/StatusBarIconPolicy.swift",
                "Core/Policies/StatusBarPresentationPolicy.swift",
                "Core/Policies/StatusBarTitlePolicy.swift",
            ]
        ),
        .testTarget(
            name: "MeetingBarLogicTests",
            dependencies: ["MeetingBarLogic"],
            path: "MeetingBarLogicTests"
        ),
    ]
)
