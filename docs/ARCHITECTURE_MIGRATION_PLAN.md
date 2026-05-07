# MeetingBar Architecture Migration Plan

Status: revised 2026-05-07. Replaces the earlier 11-phase, 30-PR plan.

Current state: ~65% of the structural work is done. Feature folders exist,
AppModel is wired, logic tests pass at 95.9%, and notifications are split.
This plan finishes the migration with fewer files and less ceremony than the
original plan required.

Related documents:

- target architecture: [`ARCHITECTURE_UPDATE.md`](ARCHITECTURE_UPDATE.md)
- contributor map of current code: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- product roadmap: [`../ROADMAP.md`](../ROADMAP.md)

---

## Design Principles

**Minimum concepts, maximum clarity.** MeetingBar is a utility app with one
main maintainer and occasional contributors. Every abstraction must earn its
place by either eliminating a real bug class or making a common contribution
task noticeably easier.

**Finish what is there before adding new layers.** The current code is 65%
migrated. Half-done architecture is worse than either the old or new design
alone.

**Methods over dispatch for simple triggers.** AppAction is kept for
data-carrying events (`eventsLoaded`, `changeProvider`). Simple system events
(`handleWake`, `handleScreenLock`) become direct methods on AppModel.

**Merge internal details, keep external boundaries.** Types that only exist to
serve one other type belong inside that file, not in their own file.

---

## Target State

From 85 files to roughly 50.

```
MeetingBar/
├── App/
│   ├── AppDelegate.swift       ← composition root, ~120 lines
│   ├── AppModel.swift          ← central state + methods, ~150 lines
│   ├── AppAction.swift         ← data-carrying actions only
│   ├── AppState.swift
│   ├── AppEnvironment.swift
│   ├── AppIntent.swift
│   ├── AppStore.swift
│   ├── LifecycleObserver.swift
│   ├── Notifications.swift
│   └── URLHandler.swift
│
├── Calendar/
│   ├── EventStore.swift        ← protocol (moved from Core/)
│   ├── AuthenticatedEventStore.swift
│   ├── CalendarRepository.swift (moved from Core/)
│   ├── EventManager.swift
│   ├── EventFiltering.swift
│   ├── EventFiltering+MeetingBar.swift
│   ├── EventSelection.swift
│   ├── EventSelection+MeetingBar.swift
│   ├── MBEvent.swift           ← moved from Core/Models/
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
│   ├── MeetingProvider.swift   ← struct + static all (replaces descriptor+registry)
│   ├── MeetingServices.swift   ← enum + localisation + icon helpers
│   ├── MeetingLinkCandidate.swift
│   ├── MeetingLinkDetection.swift
│   ├── MeetingLinkDetector.swift
│   ├── MeetingOpener.swift
│   ├── MeetingOpeningPolicy.swift
│   └── Opening/
│       ├── MeetingOpenStrategy.swift       ← complex per-provider URL transforms
│       └── MeetingOpenPreferencesMigration.swift
│
├── Notifications/
│   ├── NotificationPlanner.swift    ← pure planning (keep as-is)
│   ├── NotificationScheduler.swift  ← reconcile + content + records
│   ├── NotificationActionRunner.swift ← fullscreen / autojoin / script
│   ├── NotificationCenterDelegate.swift
│   ├── NotificationSetup.swift
│   └── EventActionPolicy.swift
│
├── StatusBar/
│   ├── StatusBarController.swift   ← thin render only (was ItemController)
│   ├── StatusBarMenuState.swift
│   ├── StatusBarMenuStateFactory.swift
│   ├── StatusBarPresentation.swift
│   ├── StatusBarPresentation+MeetingBar.swift
│   ├── StatusBarTitlePolicy.swift
│   ├── StatusBarTitlePolicy+MeetingBar.swift
│   ├── StatusBarIconPolicy.swift
│   ├── StatusBarIconPolicy+MeetingBar.swift
│   └── MenuBuilder.swift           ← reads StatusBarMenuState, zero Defaults
│
├── Settings/
│   └── AppSettings.swift           ← value type + .current factory (no singleton)
│
├── Preferences/ (moved from UI/Views/Preferences)
│   ├── GeneralTab.swift
│   ├── AppearanceTab.swift
│   ├── CalendarsTab.swift
│   ├── LinksTab.swift
│   ├── AdvancedTab.swift
│   ├── BrowserConfigView.swift
│   └── StatusTab.swift
│
├── Utilities/
│   ├── Diagnostics/
│   │   ├── DiagnosticsReport.swift
│   │   └── DiagnosticsReport+MeetingBar.swift
│   ├── Constants.swift
│   ├── Helpers.swift
│   ├── I18N.swift
│   ├── Keychain.swift
│   └── Scripts.swift
│
└── Extensions/
    ├── DefaultsKeys.swift
    ├── KeyboardShortcutsNames.swift
    ├── String.swift
    └── URL.swift
```

---

## Phase 1: Fix Build and Clear Core/

**Goal:** working build and test suite; remove the split between `Core/` and
feature folders.

**Why first:** nothing else can be verified until the build is green. The
`Core/` remnant confuses navigation — models live in two places.

### PR 1: Fix SwiftLint build error

File: `MeetingBarLogicTests/StatusBarPresentationPolicyTests.swift` line 260.
Rename the single-character variable `s` to `settings`.
Run `make test-logic` and `make test`. Both must pass.

### PR 2: Move Core/ into feature folders

Move files, update Xcode project references. No logic changes.

| From | To |
|---|---|
| `Core/Models/MBEvent.swift` | `Calendar/MBEvent.swift` |
| `Core/Models/MBEvent+Helpers.swift` | `Calendar/MBEvent+Helpers.swift` |
| `Core/Models/MBCalendar.swift` | `Calendar/MBCalendar.swift` |
| `Core/Models/ProviderHealth.swift` | `Calendar/ProviderHealth.swift` |
| `Core/EventStores/Protocol.swift` | `Calendar/EventStore.swift` |
| `Core/EventStores/CalendarRepository.swift` | `Calendar/CalendarRepository.swift` |

Delete empty `Core/` folder.
Update `Package.swift` so hostless tests still find the moved files.
Run full test suite.

**Exit criteria:** `Core/` does not exist. Build and tests pass.

---

## Phase 2: MenuBuilder From State

**Goal:** `MenuBuilder` reads `StatusBarMenuState`, not `Defaults`. Zero
direct `Defaults` reads in the status bar rendering path.

**Why:** `StatusBarMenuState` exists but is a skeleton. `MenuBuilder` still
has 29 `Defaults[...]` reads. The state centralisation goal is not met until
the renderer is fed from state.

### PR 3: Complete StatusBarMenuState and wire MenuBuilder

Steps:

1. Expand `StatusBarMenuState` to carry every value `MenuBuilder` currently
   reads from `Defaults`: event display settings, title/time format, icon
   format, meeting settings, bookmarks, browser preferences, dismissed events,
   and pending/tentative display.

2. Update `StatusBarMenuStateFactory` to populate the expanded state from
   `AppModel.state` and `AppSettings.current`.

3. Update `MenuBuilder` to accept `StatusBarMenuState` instead of reading
   `Defaults` inline. Thread the state through every `build*` method that
   currently reads a Defaults key.

4. Verify `MenuBuilderTests` still pass. Add a test for one previously
   untested Defaults-driven branch.

**Acceptance:** `grep -n "Defaults\[" MeetingBar/UI/StatusBar/MenuBuilder.swift`
returns no results.

---

## Phase 3: Notification Consolidation

**Goal:** 9 notification files → 4. Internal implementation details become
private members of `NotificationScheduler`, not separate public types.

**Why:** A contributor fixing "notification does not fire after wake" now
reads 9 files. The split was too fine — `NotificationContentFactory` (64
lines) and `NotificationRecordStore` (98 lines) are purely internal to the
scheduler. `NotificationActionScheduler` (83 lines) coordinates the same
firing logic that `NotificationScheduler` already owns.

### PR 4: Merge ContentFactory and RecordStore into Scheduler

Move the bodies of `NotificationContentFactory` and `NotificationRecordStore`
into `NotificationScheduler` as private methods and a private inner type
(or a file-private struct in the same file).

Delete `NotificationContentFactory.swift` and `NotificationRecordStore.swift`.

Update `Package.swift` to remove the deleted files from the hostless target if
they were listed.

Run tests.

### PR 5: Merge ActionScheduler into Scheduler or ActionRunner

`NotificationActionScheduler` decides *when* an action is due;
`NotificationActionRunner` *executes* it. These are adjacent steps. Move the
scheduling logic into `NotificationActionRunner` or into `NotificationScheduler`.

Delete `NotificationActionScheduler.swift`.

Run tests.

**Exit criteria:** `Notifications/` contains exactly:
`NotificationPlanner.swift`, `NotificationScheduler.swift`,
`NotificationActionRunner.swift`, `NotificationCenterDelegate.swift`,
`NotificationSetup.swift`, `EventActionPolicy.swift`.

---

## Phase 4: Meeting Provider Simplification

**Goal:** Replace `MeetingProviderDescriptor` + `MeetingProviderRegistry` +
`MeetingOpenerRegistry` + `CreateMeetingRegistry` (four types, 690 lines, two
subfolders) with one `MeetingProvider.swift` containing a plain struct and a
static `all` array.

**Why:** The registry pattern adds type ceremony without enabling anything the
simpler struct does not. `MeetingProviderRegistry` (536 lines) is the largest
single file in the codebase. Adding a provider still requires editing it.
The target: add one `static let` property and one entry in `all`.

### PR 6: Introduce MeetingProvider struct

Create `Meetings/MeetingProvider.swift`:

```swift
struct MeetingProvider: Equatable, Sendable {
    let id: String           // stable, equals MeetingServices.rawValue for built-ins
    let displayName: String
    let iconName: String
    let iconWidth: Double
    let iconHeight: Double
    let regexPattern: String?
    let nativeAppBrowserName: String?

    static let googleMeet = MeetingProvider(id: "Google Meet", ...)
    static let zoom       = MeetingProvider(id: "Zoom", ...)
    // ... all built-in providers

    static let all: [MeetingProvider] = [
        .googleMeet, .zoom, .teams, ...
    ]

    static func provider(for id: String) -> MeetingProvider? {
        all.first { $0.id == id }
    }
}
```

Opening strategies stay in `MeetingOpenStrategy.swift` — they handle complex
URL transforms (Zoom app scheme, Teams deep link, Slack huddle) and are
legitimate complexity.

Create-meeting URLs move to a static lookup on `MeetingProvider` or inline in
`MeetingServices`.

### PR 7: Remove old registry files

Update callers (`MeetingServices.swift`, `MeetingLinkDetector.swift`,
`MeetingLinkDetection.swift`, `LinksTab.swift`) to use `MeetingProvider`.

Delete:
- `Meetings/Domain/MeetingProviderDescriptor.swift`
- `Meetings/Domain/MeetingProviderRegistry.swift`
- `Meetings/Opening/MeetingOpenerRegistry.swift`
- `Meetings/Creation/CreateMeetingRegistry.swift`

Delete empty `Meetings/Domain/` and `Meetings/Creation/` folders.
Remove deprecated `meetingLinkRegexPatterns` shim from `MeetingLinkDetection.swift`.

Run full test suite. Add a test: adding a fake provider to `MeetingProvider.all`
makes it detectable by `MeetingLinkDetector`.

**Exit criteria:** `MeetingProviderRegistry` does not exist. `MeetingProvider`
is the single source of provider metadata. The `Meetings/` folder has no
subfolders except `Opening/`.

---

## Phase 5: Settings Simplification

**Goal:** Replace `SettingsStore` singleton with `AppSettings.current` static
factory. One fewer singleton, one fewer file, same result.

**Why:** `SettingsStore` at 84 lines is a thin wrapper that reads Defaults and
returns `AppSettings`. The same pattern is already used elsewhere in the
codebase (`StatusBarPresentationSettings.current`, etc.). A static factory on
the value type is simpler and requires no shared instance.

### PR 8: Convert SettingsStore to AppSettings.current

Add to `Settings/AppSettings.swift`:

```swift
extension AppSettings {
    @MainActor
    static var current: AppSettings {
        AppSettings(
            calendar: CalendarSettings(
                selectedCalendarIDs: Defaults[.selectedCalendarIDs],
                ...
            ),
            ...
        )
    }
}
```

Replace all `SettingsStore.shared.settings` call sites with `AppSettings.current`.
Delete `Settings/SettingsStore.swift`.

Run tests.

---

## Phase 6: AppModel Public API

**Goal:** System event triggers become direct methods on `AppModel`. The
`AppAction` enum stays for data-carrying events; simple triggers do not need
to be routed through a switch.

**Why:** `appModel?.send(.didWake)` and `appModel?.handleWake()` are
equivalent, but the method form is self-documenting and does not require the
caller to know about `AppAction`. AppDelegate and LifecycleObserver are the
main callers — they benefit most from the cleaner call site.

### PR 9: Add convenience methods to AppModel

```swift
extension AppModel {
    func handleWake() { send(.didWake) }
    func handleScreenLock() { send(.screenLocked) }
    func handleScreenUnlock() { send(.screenUnlocked) }
    func handleTimezoneChange() { send(.timezoneChanged) }
    func handleDayChange() { send(.dayChanged) }
    func handleCalendarStoreChange() { send(.calendarStoreChanged) }
}
```

Update `AppDelegate` and `LifecycleObserver` to call methods instead of
`send(...)`.

`AppAction` cases for system events can be kept or removed in a follow-up once
all callers are migrated. Do not remove them in this PR.

---

## Phase 7: Final Cleanup

**Goal:** documentation matches code, no deprecated shims, test suite clean.

### PR 10: Cleanup and doc update

- Move `UI/Views/Preferences/` → `Preferences/` if not already moved.
- Remove any remaining deprecated `@available(*, deprecated)` shims.
- Update `ARCHITECTURE.md` directory map to match actual file layout.
- Verify `make validate-strings` passes.
- Run `make lint`, `make test-logic`, `make test`.

---

## PR Sequence Summary

| PR | What | Files removed | Risk |
|---|---|---|---|
| 1 | Fix SwiftLint error | 0 | None |
| 2 | Move Core/ to Calendar/ | Core/ folder | Low |
| 3 | MenuBuilder from StatusBarMenuState | 0 | Medium |
| 4 | Merge ContentFactory + RecordStore into Scheduler | 2 | Low |
| 5 | Merge ActionScheduler into Scheduler/Runner | 1 | Low |
| 6 | Introduce MeetingProvider struct | 0 | Low |
| 7 | Remove old registry files | 4 + 2 folders | Medium |
| 8 | AppSettings.current replaces SettingsStore | 1 | Low |
| 9 | AppModel convenience methods | 0 | None |
| 10 | Cleanup + doc update | shims | None |

Ten PRs. No phase requires more than one day of focused work.

---

## What Does Not Change

- `AppAction` enum stays. It earns its place for data-carrying cases
  (`eventsLoaded`, `changeProvider`, notification responses).
- `AppEnvironment` stays. Closure-based injection is already in place and works.
- `CalendarRepository` stays. It owns provider switching cleanly.
- `MeetingOpenStrategy.swift` stays. Complex URL transforms for Zoom, Teams,
  Slack, and Riverside are real per-provider logic, not ceremony.
- `+MeetingBar` adapter files stay where they already exist. Do not add new
  ones — put new bridges inline.
- Hostless SwiftPM logic tests stay. Update `Package.swift` in the same PR
  as any file move.

---

## Definition of Done

The migration is complete when:

- `Core/` folder does not exist.
- `MenuBuilder` has zero direct `Defaults` reads.
- `Notifications/` has six files, not nine.
- `MeetingProviderRegistry`, `MeetingProviderDescriptor`, `MeetingOpenerRegistry`,
  and `CreateMeetingRegistry` do not exist.
- `SettingsStore` does not exist; `AppSettings.current` is the single factory.
- `AppDelegate` uses `appModel.handleWake()` style, not `send(.didWake)`.
- `make test-logic` passes with coverage ≥ 95%.
- `make test` passes.
- `make lint` passes with zero errors.
- `ARCHITECTURE.md` directory map matches actual file layout.
- Total Swift file count is below 55.

---

## Stop Conditions

Pause and reassess if:

- A PR needs to touch more than two high-risk files (`EventManager`,
  `StatusBarItemController`, `MenuBuilder`, `AppDelegate`, `NotificationScheduler`).
- A change to `MeetingProvider` breaks bookmark or browser-preference decoding
  for existing users.
- Merging notification files makes a single file exceed 300 lines — split
  differently instead.
- Test coverage drops below 93% after a merge.
