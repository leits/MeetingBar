# MeetingBar - macOS Menu-Bar Calendar App

**Generated:** 2026-04-23
**Branch:** feature/spec-kit-opencode

## OVERVIEW
Menu-bar app showing calendar meetings with 50+ meeting service integrations. Written in Swift 5.0, uses AppKit + EventKit.

## STRUCTURE
```
MeetingBar/
├── App/              # AppDelegate, AppStore, Notifications, AppIntent
├── Core/
│   ├── EventStores/  # Calendar data access
│   ├── Managers/     # ActionsOnEventStart, EventManager
│   └── Models/       # Data models
├── Services/         # MeetingServices (28k), Scripts
├── UI/
│   ├── StatusBar/    # Menu-bar status item
│   └── Views/        # Preferences, Onboarding
├── Utilities/        # Constants, Helpers, I18N, Keychain
└── Extensions/       # Swift extensions
```

## WHERE TO LOOK
| Task | Location |
|------|----------|
| Menu-bar logic | `UI/StatusBar/`, `App/AppDelegate.swift` |
| Calendar events | `Core/EventStores/`, `Core/Managers/EventManager.swift` |
| Meeting join logic | `Services/MeetingServices.swift` |
| App settings | `App/AppStore.swift`, `UI/Views/Preferences/` |
| Localization | `Utilities/I18N.swift` |

## CODE MAP (Complex Files)
| File | Lines | Role |
|------|-------|------|
| MeetingServices.swift | ~28k | 50+ meeting service URL patterns |
| Helpers.swift | ~9k | Shared utilities |
| Constants.swift | ~7k | App constants, service configs |
| AppDelegate.swift | ~12k | App lifecycle, menu setup |
| ActionsOnEventStart.swift | ~7k | Event automation actions |

## CONVENTIONS
- SwiftLint enforced (`.swiftlint.yml`)
- Line length: warn 200, error 250
- Cyclomatic complexity: warn at 15
- Identifier min length: 2 chars
- Allow `_` for unused params
- Force unwrap/try/cast: disabled rules (opt-in safety)
- No XcodeGen - uses direct `.xcodeproj`

## BUILD & TEST
```bash
xcodebuild -project MeetingBar.xcodeproj -scheme MeetingBar -configuration Debug build
xcodebuild test -project MeetingBar.xcodeproj
```

## KEY LIBRARIES
- `KeyboardShortcuts` - global hotkeys
- `Defaults` - settings persistence
- `SwiftyStoreKit` - in-app purchases

## NOTES
- App runs as menu-bar agent (LSUIElement = true)
- Uses macOS Calendar app data via EventKit
- 50+ meeting service URL patterns in MeetingServices

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
