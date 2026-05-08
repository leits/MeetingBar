# Preferences and Onboarding Redesign Plan

Status: revised 2026-05-08. Most of the structural work the earlier plan
called for has already landed as part of the 5.0 architecture migration.
This document covers what is left.

Related: [`ARCHITECTURE.md`](ARCHITECTURE.md), [`../ROADMAP.md`](../ROADMAP.md).

---

## What Is Already Done

The 5.0 migration unblocked most of the original plan:

- `AppSettings.current` is the single Defaults boundary; pure logic receives
  value-typed snapshots.
- `MeetingProvider.all` is a flat catalogue. `LinksTab` already iterates the
  registry instead of hard-coding rows per provider.
- Onboarding does not reach into `AppDelegate` — `OnboardingHandler` is
  injected through `EnvironmentObject`, and `AppDelegate` sets `appModel` on
  it after setup completes so `CalendarsScreen` can observe app state.
- Old per-provider browser keys (`meetBrowser`, `zoomBrowser`, …) migrate to
  the unified `providerBrowsers` map via `MeetingOpenPreferencesMigration`.
- `AppModel` exposes `AppAction` for data-carrying intents and direct
  `handle*()` methods for system triggers, so views can dispatch settings
  changes without touching `AppDelegate`.

The realistic remaining scope is much smaller than the original plan
suggested. `@Default` bindings in Preferences views are a SwiftUI convenience
and stay — the 5.0 boundary rule applies to feature logic, not view bindings.

---

## What Is Left

### 1. Direct `Defaults[...]` reads outside the SwiftUI binding layer

In `MeetingBar/UI/Views/`, ten direct reads/writes remain that aren't
`@Default` bindings:

- `Preferences/CalendarsTab.swift` — six reads/writes mutating
  `selectedCalendarIDs` as an array directly. Should go through `AppModel`
  (an action like `toggleCalendarSelection(id:)`) so a future provider
  switch or selected-calendar caching can sit on the model side.
- `Preferences/StatusTab.swift` — two snapshot reads (`eventStoreProvider`,
  `selectedCalendarIDs.count`) used to render diagnostics. Should read from
  `AppSettings.current` or a `DiagnosticsModel` snapshot.
- `Preferences/GeneralTab.swift` — one read of `appVersion` for display.
  Trivial; can move to `AppSettings` or stay as a constant lookup.
- `Onboarding/AccessScreen.swift` — one write of `eventStoreProvider` during
  provider selection. Should be an `AppAction.providerSelected(...)` or a
  call into `OnboardingHandler` that internally dispatches.

### 2. Folder move: `UI/Views/{Preferences,Onboarding}/` → root

`UI/Views/` is now a mixed bag (Preferences, Onboarding, FullscreenNotification,
DayTimelineView, Changelog, Shared). Hoisting Preferences and Onboarding to the
project root matches the feature-folder layout the rest of the app already uses
(Calendar/, Meetings/, Notifications/, …).

Mechanical move; no code changes required besides project navigation.

### 3. Permission and auth display state

EventKit permission, Google sign-in, and notification permission are each
discovered independently by views that need them. A small shared display
state (one struct per permission, populated by a model) prevents future
contributors from rediscovering the same logic.

Smallest useful surface:

```swift
enum PermissionState: Equatable {
    case unknown, denied, granted, expired(reason: String)
}

struct CalendarProviderDisplayState: Equatable {
    var provider: EventStoreProvider
    var supportsSignOut: Bool
    var permission: PermissionState
    var health: ProviderHealth
}
```

`CalendarsTab`, `StatusTab`, and onboarding access errors all consume this
shape instead of recomputing it.

### 4. Diagnostics shared surface

`StatusTab` builds its diagnostics view from `EventManager` + `Defaults`.
A `DiagnosticsModel` populated once and reused by `StatusTab`,
onboarding access errors, and the issue-report exporter would prevent
divergence and shrink the per-tab view.

### 5. Onboarding state machine

Onboarding is currently `OnboardingHandler` plus a screen sequence wired
through `ViewRouter`. An explicit step enum makes the flow easier to test
and makes future step insertion (notification permission step, provider
permission retry) cheap.

```swift
enum OnboardingStep: Hashable {
    case welcome
    case calendarAccess
    case calendarSelection
    case ready
}
```

Completion stays an explicit action through `OnboardingHandler` /
`AppModel`, which is already the pattern.

### 6. Settings migration versioning

Currently each migration is ad-hoc (`MeetingOpenPreferencesMigration` for
provider browsers; bookmarks moved to provider IDs in the `MeetingProvider`
PR). A small `SettingsMigration` helper that records a version in `Defaults`
and runs migrations once would make future schema changes safer.

Defer until the next migration is needed — adopting a framework
prophylactically is the kind of work the 5.0 plan deliberately avoided.

---

## Out Of Scope

- Replacing `NSStatusItem` with `MenuBarExtra`.
- A view-model layer for every tab. Most tabs are thin enough that
  introducing `PreferencesModel` / `CalendarSettingsModel` etc. adds more
  ceremony than clarity. Add a model only when a view contains testable logic
  beyond bindings (e.g. permission resolution, async sign-in).
- A `Settings/Components/` library of custom row/section views. SwiftUI's
  built-in `Form`/`Section`/`LabeledContent` already cover the common cases.
  Add shared components only when copy-paste duplication crosses three
  views.
- A full visual rebrand or new settings.

---

## Migration Sequence

Small, independent PRs. Each one ships on its own.

1. ✅ **Route `CalendarsTab` selection through `AppModel`.** Done in
   `836eeaf`. `AppEnvironment.toggleCalendarSelection` + `AppModel`
   convenience method, `CalendarRow` uses `@Default` for read binding,
   no view writes `Defaults[.selectedCalendarIDs]` directly.

2. ✅ **Move `UI/Views/Preferences/` → `Preferences/`.** Done in `4b830ac`
   alongside the Onboarding move.

3. ✅ **Move `UI/Views/Onboarding/` → `Onboarding/`.** Done in `4b830ac`.

4. ✅ **Replace remaining `Defaults[...]` reads.** Done in `e4a22b8`.
   `StatusTab` reads through `AppSettings.current`, `GeneralTab` reads
   the bundle version directly, `AccessScreen` drops the redundant
   provider write that `EventManager.changeEventStoreProvider` already
   handles.

5. ⏸ **`PermissionState` and `CalendarProviderDisplayState`.** Deferred.
   Auditing the code, there is barely any duplicated permission discovery
   to consolidate yet — `AccessDeniedBanner` uses a heuristic ("calendars
   list empty + EventKit") rather than calling `EKEventStore.authorizationStatus`,
   `ProviderHealth.authRequired` already covers the Google-signed-out case,
   and Google `authState` lives in `GCEventStore`. Adding the types now would
   be infrastructure-without-need. Revisit when a real UX issue (user
   confusion about denied permission, retry path) appears.

6. ✅ **Diagnostics shared assembly.** Done in `968811b`. Added
   `DiagnosticsContext.current(eventManager:)` factory plus
   `DiagnosticsClipboard.copy(...)` helper in the diagnostics adapter.
   `StatusTab.DiagnosticsSection` now calls the helper directly; future
   onboarding error states reuse the same factory without duplicating
   the assembly.

7. ✅ **`OnboardingStep` state machine.** Done in `415697d`. Renamed
   `Screens` → `OnboardingStep` and `ViewRouter` → `OnboardingRouter`,
   replaced the hand-rolled `PassthroughSubject` plumbing with `@Published`,
   and switched `OnboardingView` to a switch-based render.

8. ⏸ **`SettingsMigration` helper.** Deferred per the original plan;
   add only when the next breaking schema change actually arrives.

Manual QA before release: provider switch, EventKit allowed/denied,
Google sign-in success/failure/cancel, first-launch onboarding, custom
regex.

---

## Definition Of Done

The migration is complete when:

- `Preferences/` and `Onboarding/` live at the project root, not under `UI/Views/`.
- The only direct `Defaults[...]` reads in `Preferences/` and `Onboarding/`
  are inside SwiftUI `@Default` bindings.
- Calendar selection is mutated through `AppModel` actions, not by writing
  `Defaults[.selectedCalendarIDs]` from the view.
- A `PermissionState` (and `CalendarProviderDisplayState`) exists and is the
  single source of permission display logic across views.
- Diagnostics rendering uses a shared `DiagnosticsModel`, not raw
  `EventManager` + `Defaults`.
- Onboarding routes through an explicit `OnboardingStep` enum.
- Existing user settings (bookmarks, browser preferences, onboarding
  completion) survive the changes.
