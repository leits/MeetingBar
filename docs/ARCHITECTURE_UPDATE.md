# MeetingBar Architecture Update

Status: revised 2026-05-07. Describes the target state after the migration in
[`ARCHITECTURE_MIGRATION_PLAN.md`](ARCHITECTURE_MIGRATION_PLAN.md).

[`ARCHITECTURE.md`](ARCHITECTURE.md) maps the current code as it exists today.
This document describes where the code is heading and why.

---

## Design Principles

**One concept per real problem.** Every abstraction must either eliminate a
real bug class or make a common contribution easier. If it does neither, it
should not exist.

**Methods over dispatch for system triggers.** AppModel exposes `handleWake()`,
`handleScreenLock()` etc. as direct methods. AppAction is reserved for
data-carrying events that benefit from an explicit type (`eventsLoaded`,
`changeProvider`, notification responses).

**Internal details stay internal.** A type that only serves one other type
belongs inside that file. `NotificationContentFactory` and
`NotificationRecordStore` are implementation details of `NotificationScheduler`,
not separate public concerns.

**Data over type ceremony for provider registries.** Meeting providers are a
struct with a static `all` array. No registry enum, no descriptor/registry
split. Adding a provider means adding one static property.

---

## Goals

- A new contributor answers "where does this feature live?" in under a minute.
- App state is not spread across five owners.
- Common behavior changes touch one feature folder.
- Adding a meeting provider requires one struct property, one pattern, one
  icon, and tests.
- Pure logic stays easy to test.
- AppKit, EventKit, UserNotifications, Keychain, network, AppleScript, and URL
  opening stay at named boundaries.

---

## Non-Goals

- SwiftPM core package as a separate shipped product.
- TCA or any other state management framework.
- Full rewrite of AppKit lifecycle.
- Replacing `NSStatusItem` with `MenuBarExtra`.
- Broad UI redesign.
- New user-facing behavior during the migration.

---

## Target Data Flow

```
Calendar providers
  ↓  fetch (async, off main)
EventManager / CalendarRepository
  ↓  @Published events + calendars + health
AppModel (@MainActor ObservableObject)
  ↓  computed: nextEvent, statusBarPresentation, notificationPlans
  ├─→ StatusBarController  →  NSStatusItem (render only)
  ├─→ MenuBuilder          ←  StatusBarMenuState (no Defaults reads)
  └─→ NotificationScheduler  →  UNUserNotificationCenter (reconcile)

User / system events
  →  AppModel.handleWake() / .handleScreenLock() / .send(.changeProvider)
  →  state mutation + side effects through AppEnvironment
```

Renderers receive derived state. They do not decide what the next event is,
which notifications should exist, or which meeting link wins.

---

## Target Directory Layout

```
MeetingBar/
├── App/
│   ├── AppDelegate.swift       — composition root, ~120 lines
│   ├── AppModel.swift          — state owner, methods, ~150 lines
│   ├── AppAction.swift         — data-carrying events only
│   ├── AppState.swift
│   ├── AppEnvironment.swift
│   ├── AppIntent.swift
│   ├── AppStore.swift
│   ├── LifecycleObserver.swift
│   ├── Notifications.swift
│   └── URLHandler.swift
│
├── Calendar/
│   ├── EventStore.swift        — provider protocol
│   ├── CalendarRepository.swift — owns active provider, switches, preserves on failure
│   ├── EventManager.swift      — refresh pipeline (Combine)
│   ├── EventFiltering.swift    — pure filtering logic [SPM]
│   ├── EventFiltering+MeetingBar.swift
│   ├── EventSelection.swift    — pick next event [SPM]
│   ├── EventSelection+MeetingBar.swift
│   ├── MBEvent.swift
│   ├── MBEvent+Helpers.swift
│   ├── MBCalendar.swift
│   ├── ProviderHealth.swift
│   └── Providers/
│       ├── EventKit/
│       │   └── EventKitEventStore.swift
│       └── Google/
│           ├── GoogleCalendarEventStore.swift
│           └── GoogleCalendarPolicy.swift
│
├── Meetings/
│   ├── MeetingProvider.swift   — struct + static all (single source of provider metadata)
│   ├── MeetingServices.swift   — enum + localization + icon helpers
│   ├── MeetingLinkCandidate.swift
│   ├── MeetingLinkDetection.swift
│   ├── MeetingLinkDetector.swift
│   ├── MeetingOpener.swift
│   ├── MeetingOpeningPolicy.swift
│   └── Opening/
│       ├── MeetingOpenStrategy.swift         — per-provider URL transforms (Zoom, Teams, Slack…)
│       └── MeetingOpenPreferencesMigration.swift
│
├── Notifications/
│   ├── NotificationPlanner.swift      — pure: events + settings → [NotificationPlan] [SPM]
│   ├── NotificationScheduler.swift    — reconcile UN requests; owns content + record logic
│   ├── NotificationActionRunner.swift — executes fullscreen / autojoin / script
│   ├── NotificationCenterDelegate.swift — UNUserNotificationCenterDelegate → AppAction
│   ├── NotificationSetup.swift
│   └── EventActionPolicy.swift        — should action fire? [SPM]
│
├── StatusBar/
│   ├── StatusBarController.swift      — owns NSStatusItem, render only
│   ├── StatusBarMenuState.swift       — value type with all menu-building inputs
│   ├── StatusBarMenuStateFactory.swift — builds state from AppModel
│   ├── StatusBarPresentation.swift    — mode + presenter [SPM]
│   ├── StatusBarPresentation+MeetingBar.swift
│   ├── StatusBarTitlePolicy.swift     — title text [SPM]
│   ├── StatusBarTitlePolicy+MeetingBar.swift
│   ├── StatusBarIconPolicy.swift      — icon selection [SPM]
│   ├── StatusBarIconPolicy+MeetingBar.swift
│   └── MenuBuilder.swift              — builds NSMenu from StatusBarMenuState
│
├── Settings/
│   └── AppSettings.swift              — value type groups + .current factory
│
├── Preferences/
│   ├── GeneralTab.swift
│   ├── AppearanceTab.swift
│   ├── CalendarsTab.swift
│   ├── LinksTab.swift                 — driven by MeetingProvider.all
│   ├── AdvancedTab.swift
│   ├── BrowserConfigView.swift
│   └── StatusTab.swift
│
└── Utilities/
    ├── Diagnostics/
    │   ├── DiagnosticsReport.swift
    │   └── DiagnosticsReport+MeetingBar.swift
    ├── Constants.swift
    ├── Helpers.swift
    ├── I18N.swift
    ├── Keychain.swift
    └── Scripts.swift
```

Target: under 55 Swift files.

---

## AppModel

`AppModel` is the single state owner. It publishes derived state that renderers
observe. It receives explicit `AppAction`s for data-carrying events and exposes
direct methods for system triggers.

```swift
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AppState

    // System trigger methods — callers do not need to import AppAction
    func handleWake() { send(.didWake) }
    func handleScreenLock() { send(.screenLocked) }
    func handleScreenUnlock() { send(.screenUnlocked) }
    func handleTimezoneChange() { send(.timezoneChanged) }
    func handleDayChange() { send(.dayChanged) }
    func handleCalendarStoreChange() { send(.calendarStoreChanged) }

    // Data-carrying dispatch
    func send(_ action: AppAction) { ... }
}
```

Hard limits:

- No AppKit, EventKit, UserNotifications, AppAuth, Keychain, or AppleScript
  imports in `AppModel`.
- No direct `Defaults` reads in `AppModel`.
- Side effects go through `AppEnvironment`.

`AppState` holds raw state only:

- `calendars: [MBCalendar]`
- `events: [MBEvent]`
- `activeProvider: EventStoreProvider`
- `screenIsLocked: Bool`

Derived state is computed from `AppState` by the feature components that need
it (`StatusBarPresentation`, `NotificationPlanner`, `StatusBarMenuState`).

---

## Meeting Providers

Meeting provider metadata lives in one struct with a static array. No registry
type, no descriptor/registry split.

```swift
struct MeetingProvider: Equatable, Sendable {
    let id: String
    let displayName: String
    let iconName: String
    let iconWidth: Double
    let iconHeight: Double
    let regexPattern: String?
    let nativeAppBrowserName: String?

    static let googleMeet = MeetingProvider(id: "Google Meet", displayName: "Google Meet", ...)
    static let zoom       = MeetingProvider(id: "Zoom", ...)
    // ... all built-in providers

    static let all: [MeetingProvider] = [.googleMeet, .zoom, .teams, ...]

    static func provider(for id: String) -> MeetingProvider? {
        all.first { $0.id == id }
    }
}
```

Adding a simple provider: one `static let` property, one entry in `all`, and
tests. No other file needs to change.

Complex opening behavior (Zoom app scheme, Teams deep link, Slack huddle,
Riverside multi-scheme) stays in `MeetingOpenStrategy.swift`. These are
real per-provider rules, not ceremony.

---

## Settings

Settings live in grouped value types. `AppSettings.current` is the single
factory that reads Defaults. No singleton.

```swift
struct AppSettings: Equatable {
    var calendar: CalendarSettings
    var events: EventDisplaySettings
    var statusBar: StatusBarSettings
    var menu: MenuSettings
    var notifications: NotificationSettings
    var meetings: MeetingSettings
    var advanced: AdvancedSettings
}

extension AppSettings {
    @MainActor
    static var current: AppSettings { ... reads Defaults ... }
}
```

Pure logic receives `AppSettings` or sub-structs by value. It does not read
`Defaults` directly. Preferences views may keep `@Default` bindings — that is
a SwiftUI convenience, not a bug.

---

## Notifications

Five responsibilities, six files:

| File | Responsibility |
|---|---|
| `NotificationPlanner.swift` | Pure: events + settings → desired plans |
| `NotificationScheduler.swift` | Reconcile UN requests + content building + record keeping |
| `NotificationActionRunner.swift` | Execute fullscreen / autojoin / script |
| `NotificationCenterDelegate.swift` | Translate UN responses to AppAction |
| `NotificationSetup.swift` | Request UN authorization |
| `EventActionPolicy.swift` | Should a given action fire for this event? |

`NotificationContentFactory` and `NotificationRecordStore` are internal to
`NotificationScheduler`. They do not need their own files.

---

## StatusBar

`StatusBarController` owns the `NSStatusItem` and renders. It does not store
events, compute next event, or read `Defaults`.

`StatusBarMenuState` carries everything `MenuBuilder` needs. `MenuBuilder`
reads only from this state, never from `Defaults` directly.

```
AppModel.state
  → StatusBarMenuStateFactory.make(...)
  → StatusBarMenuState
  → MenuBuilder.build(...)
  → NSMenu
```

---

## Calendar Providers

`EventStore` and `AuthenticatedEventStore` are separate protocols. EventKit
does not stub OAuth methods.

`CalendarRepository` owns provider selection and switching, preserves last
known good data on failure, and exposes a clean fetch API to `EventManager`.

Adding a future provider means adding a file in `Calendar/Providers/` and
implementing the protocols. No other code changes are required.

---

## Testing

Hostless SwiftPM tests (`make test-logic`) cover pure decisions. Host tests
(`make test`) cover AppKit rendering and integration.

Coverage targets:

| Area | Target |
|---|---|
| Pure logic (policies, planner, filtering) | ≥ 95% |
| Meeting provider detection / ranking | ≥ 95% |
| Notification schedule diff | ≥ 90% |
| AppKit renderers | characterization |

---

## Definition of Done

The architecture is complete when:

- `Core/` does not exist.
- `MenuBuilder` has zero direct `Defaults` reads.
- `Notifications/` has six files.
- `MeetingProviderRegistry`, `MeetingProviderDescriptor`, `MeetingOpenerRegistry`,
  and `CreateMeetingRegistry` do not exist.
- `SettingsStore` does not exist.
- `AppDelegate` uses `appModel.handleWake()` style for system triggers.
- Total Swift file count is under 55.
- `make test-logic` passes at ≥ 95% coverage.
- `make test` passes with zero failures.
- `ARCHITECTURE.md` matches the actual file layout.
