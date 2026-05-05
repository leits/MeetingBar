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
                "Preview Content"
            ],
            sources: [
                // Utilities/Diagnostics
                "Utilities/Diagnostics/DiagnosticsReport.swift",
                // Notifications
                "Notifications/EventActionPolicy.swift",
                "Notifications/NotificationPlanner.swift",
                // Calendar
                "Calendar/EventFiltering.swift",
                "Calendar/EventSelection.swift",
                "Calendar/Providers/Google/GoogleCalendarPolicy.swift",
                // Meetings
                "Meetings/MeetingLinkCandidate.swift",
                "Meetings/MeetingLinkDetection.swift",
                "Meetings/MeetingLinkDetector.swift",
                "Meetings/MeetingOpeningPolicy.swift",
                // UI/StatusBar
                "UI/StatusBar/StatusBarIconPolicy.swift",
                "UI/StatusBar/StatusBarPresentation.swift",
                "UI/StatusBar/StatusBarTitlePolicy.swift",
                // Meetings/Domain — pure provider descriptors and registry.
                "Meetings/Domain/MeetingProviderDescriptor.swift",
                "Meetings/Domain/MeetingProviderRegistry.swift"
            ]
        ),
        .testTarget(
            name: "MeetingBarLogicTests",
            dependencies: ["MeetingBarLogic"],
            path: "MeetingBarLogicTests"
        )
    ]
)
