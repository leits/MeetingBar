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
            path: "MeetingBar/Core/Policies",
            exclude: [
                "DiagnosticsReport.swift",
                "EventFilterPolicy+MeetingBar.swift",
                "EventSelectionPolicy+MeetingBar.swift"
            ],
            sources: [
                "EventActionPolicy.swift",
                "EventFilterPolicy.swift",
                "EventSelectionPolicy.swift",
                "MeetingLinkDetection.swift",
                "MeetingLinkDetector.swift",
                "NotificationPlanningPolicy.swift"
            ]
        ),
        .testTarget(
            name: "MeetingBarLogicTests",
            dependencies: ["MeetingBarLogic"],
            path: "MeetingBarLogicTests"
        )
    ]
)
