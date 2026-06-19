# Contributing to MeetingBar

MeetingBar welcomes focused bug fixes, meeting-service integrations, reliability improvements, translations, and documentation updates.

## GitHub Workflow

Use GitHub issues for public bugs and feature requests. Keep pull requests small enough to review in one pass, and describe:

* What changed and why
* User-visible behavior changes
* Tests or validation commands you ran
* Any dependency, entitlement, signing, URL scheme, script, workflow, or base-localization changes

## Bug Reports

Good bug reports include:

* MeetingBar version and macOS version
* Calendar provider: macOS Calendar or Google Calendar
* Meeting service when relevant: Zoom, Google Meet, Microsoft Teams, Webex, etc.
* Steps to reproduce
* Expected behavior and actual behavior
* Whether manual refresh, relaunch, or reconnect changes the result
* Sanitized event title, description, location, URL fields, screenshots, or logs when useful

## Building Locally

MeetingBar is a macOS app built with Xcode, Swift 6, AppKit, SwiftUI, and Xcode-managed Swift Package dependencies.

For local signing, create `XCConfig/DevTeamOverride.xcconfig` with your Apple development team. This file is git-ignored, so you do not need to change the Xcode project:

```xcconfig
DEVELOPMENT_TEAM = <your development team id>
```

Common validation commands:

```bash
make build            # Debug build
make test             # SwiftPM logic tests + Xcode app-hosted tests with coverage
make test-logic       # Hostless SwiftPM logic tests only
make lint             # SwiftLint
make validate-strings # Verify English localization keys used by .loco()
```

Unsigned local Debug builds may print entitlement or signing warnings because code signing is disabled. That warning is expected for local verification; signed Release builds still need a real signing check.

## Architecture And Dependencies

Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before changing app flow, calendar providers, meeting-link detection, notifications, status-bar rendering, settings, package dependencies, entitlements, or release-sensitive configuration.

Direct app dependencies are Xcode Swift Package references pinned by `MeetingBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. `Package.swift` defines the hostless `MeetingBarLogic` package used for fast policy tests. Do not update only `Package.resolved`; change the Xcode package requirement intentionally and review the resolved diff. StoreKit is a system framework, not an external package dependency.

Update `CHANGELOG.md` for user-visible changes and notable architecture, dependency, or release-process changes. For new source strings, update `MeetingBar/Resources /Localization /en.lproj/Localizable.strings` and run `make validate-strings`; non-English translations are managed through Weblate.

## License

By contributing, you agree that your contributions are licensed under the Apache License 2.0.
