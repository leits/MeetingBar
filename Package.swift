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
                "EventFilterPolicy.swift",
                "EventSelectionPolicy+MeetingBar.swift",
                "MeetingLinkDetector.swift"
            ],
            sources: [
                "EventActionPolicy.swift",
                "EventSelectionPolicy.swift",
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
