# MeetingBar Constitution

## Core Principles

### I. Swift Quality Standards
- **SwiftLint enforced** (`.swiftlint.yml` configured)
- Line length: warn 200, error 250
- Cyclomatic complexity: warn at 15
- Identifier min length: 2 chars
- Allow `_` for unused params
- **No force unwrap/try/cast** (disabled rules - opt-in safety only)
- Use optional chaining and guard statements

### II. Architecture
- **MVVM-lite pattern** for UI components
- Clear separation: UI (Views) / Business Logic (Managers) / Data (Models, EventStores)
- Single responsibility per module
- Core services isolated in `Core/` directory
- UI-specific code in `UI/` directory
- Shared utilities in `Utilities/` and `Extensions/`

### III. Menu-Bar App Constraints
- App runs as **LSUIElement = true** (no dock icon)
- Must be lightweight and responsive (menu-bar apps need fast launch)
- Minimize memory footprint
- Respect system resources (CPU, battery)

### IV. Calendar & Privacy
- Uses **EventKit** for calendar access (macOS Calendar app integration)
- Respect user privacy - only request necessary calendar permissions
- Store locally only - no external data transmission without user consent
- Handle calendar permission denied gracefully

### V. Meeting Service Integration
- Support 50+ meeting services via URL pattern matching
- MeetingServices.swift is the single source of truth for service detection
- Follow existing URL parsing patterns for new services
- Test new services manually before committing

### VI. Build & Deployment
- Uses **direct `.xcodeproj`** (no XcodeGen)
- Build: `xcodebuild -project MeetingBar.xcodeproj -scheme MeetingBar -configuration Debug build`
- Test: `xcodebuild test -project MeetingBar.xcodeproj`
- Target: macOS 10.15+ (Catalina and later)

## Development Workflow

### Code Review
- All changes should build successfully before PR
- Run SwiftLint locally before committing
- Test on actual macOS (not just CI)

### Dependencies
- **KeyboardShortcuts** - global hotkey management
- **Defaults** - settings persistence
- **SwiftyStoreKit** - in-app purchases
- Avoid adding dependencies unless necessary

### macOS-Specific Patterns
- Use AppKit for menu-bar and status items
- Use SwiftUI for preferences/views where appropriate
- Respect macOS Human Interface Guidelines
- Support both light and dark mode

## Governance

- Constitution supersedes all other practices
- Amendments require testing on actual macOS
- Complexity must be justified
- For runtime development guidance, refer to `AGENTS.md`

**Version**: 1.0.0 | **Ratified**: 2026-04-23 | **Last Amended**: 2026-04-23
