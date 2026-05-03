# Preferences and Onboarding Redesign Plan

Status: proposed UI architecture and migration plan for the 5.0 architecture
work.

This document is not a cosmetic redesign brief. Preferences and onboarding are
currently coupled to old storage, provider, and app-lifecycle boundaries. They
should be migrated as part of the architecture update so the app does not need a
second settings redesign after `SettingsStore`, meeting providers, calendar
providers, and `AppModel` land.

Related documents:

- target architecture: [`ARCHITECTURE_UPDATE.md`](ARCHITECTURE_UPDATE.md);
- execution plan: [`ARCHITECTURE_MIGRATION_PLAN.md`](ARCHITECTURE_MIGRATION_PLAN.md);
- product roadmap: [`../ROADMAP.md`](../ROADMAP.md).

---

## Decision Summary

Preferences and onboarding should move to a shared Settings feature.

Target shape:

- `SettingsStore` and `AppSettings` live under `Settings/`, not `App/`;
- Preferences and onboarding use shared settings components and view models;
- views bind to view models or `SettingsStore` bindings, not directly to
  `Defaults`;
- views send app-level intent through `AppAction`, not by reaching into
  `AppDelegate`, `EventManager`, or status bar controllers;
- calendar provider UI is driven by `CalendarRepository` and provider metadata;
- meeting settings UI is driven by `MeetingProviderRegistry`, not hard-coded
  provider rows;
- onboarding is a state machine over setup steps, not a separate mini-app that
  creates its own `EventManager`;
- the visual update is quiet, compact, and utility-focused, not a marketing
  page or card-heavy redesign.

This keeps one source of truth for settings while allowing Preferences and
Onboarding to present different flows.

---

## Current Problems To Fix

The current SwiftUI views are useful but structurally tied to old architecture.

### Direct Defaults Everywhere

Preferences tabs use `@Default` and `Defaults[...]` directly. This makes each
view a persistence owner and makes settings changes hard to route through
`AppModel`.

Examples:

- `LinksTab` owns browser settings, bookmarks, and create-meeting settings;
- `AppearanceTab` owns event filtering, status bar, and menu presentation keys;
- `AdvancedTab` owns scripts, custom regexes, and event filter regexes;
- `CalendarsTab` mutates selected calendar IDs directly.

Final state: direct `Defaults` / `@Default` usage is allowed only in
`SettingsStore`, migration adapters, and a narrow documented binding adapter if
SwiftUI needs one.

### Provider UI Is Hard-Coded

`LinksTab` has one row per known provider browser setting and create-meeting
choices are represented by separate enums. This conflicts with the target
meeting provider registry.

Final state: the UI renders provider descriptors:

```text
MeetingProviderRegistry
  -> MeetingProviderDescriptor
  -> MeetingProviderSettingsRow
```

Adding a simple provider should not require editing `LinksTab`.

### Onboarding Reaches Into AppDelegate

Onboarding currently performs app setup by reaching into
`NSApplication.shared.delegate`, creating `EventManager`, setting Defaults, and
calling `setup()`.

Final state: onboarding sends explicit setup actions through an
`OnboardingModel` or `AppModel` dependency. It should not instantiate app
services directly.

### Preferences And Onboarding Duplicate Product Decisions

Onboarding reuses some Preferences controls, but it does so through views that
already know too much about Defaults and EventManager. The two flows should
share smaller domain components instead:

- calendar provider picker;
- calendar selection list;
- meeting provider opener preferences;
- notification permission and timing controls;
- diagnostics/error status components.

### Layout Is Dense But Not Structured

Many sections are built from ad hoc `HStack`s, fixed widths, and local labels.
The app should stay compact, but rows need a consistent layout system so long
localized strings, small windows, and accessibility font sizes do not break the
screen.

---

## Target Directory Layout

The architecture update should treat settings UI as a feature.

```text
MeetingBar/
+-- Settings/
|   +-- AppSettings.swift
|   +-- SettingsStore.swift
|   +-- SettingsMigration.swift
|   +-- SettingsBindingAdapter.swift
|
|   +-- Components/
|   |   +-- SettingsSection.swift
|   |   +-- SettingsRow.swift
|   |   +-- SettingsInlineMessage.swift
|   |   +-- CalendarProviderPicker.swift
|   |   +-- CalendarSelectionList.swift
|   |   +-- MeetingProviderSettingsList.swift
|   |   +-- NotificationTimingControls.swift
|   |   +-- ScriptEditor.swift
|   |   +-- DiagnosticsPanel.swift
|   |
|   +-- Preferences/
|   |   +-- PreferencesView.swift
|   |   +-- PreferencesModel.swift
|   |   +-- PreferencesRoute.swift
|   |   +-- GeneralSettingsView.swift
|   |   +-- CalendarSettingsView.swift
|   |   +-- MeetingSettingsView.swift
|   |   +-- NotificationSettingsView.swift
|   |   +-- AppearanceSettingsView.swift
|   |   +-- AdvancedSettingsView.swift
|   |   +-- StatusSettingsView.swift
|   |
|   +-- Onboarding/
|       +-- OnboardingView.swift
|       +-- OnboardingModel.swift
|       +-- OnboardingStep.swift
|       +-- OnboardingCompletion.swift
```

`App/` should keep composition and app state:

```text
App/
  AppDelegate.swift
  AppModel.swift
  AppState.swift
  AppAction.swift
  AppEnvironment.swift
```

This is a small improvement over placing `AppSettings` inside `App/`.
Persistent settings are a feature boundary, not process lifecycle.

---

## Preferences Information Architecture

The current tabs are close, but the content should be grouped by user task and
provider ownership.

Recommended sections:

| Route | Purpose | Main owner |
|---|---|---|
| General | launch, language, shortcuts, basic behavior | Settings |
| Calendars | account/provider, permissions, selected calendars, provider health | Calendar |
| Meetings | provider open preferences, bookmarks, create meeting, custom providers/regex | Meetings |
| Notifications | start/end reminders, snooze, fullscreen, auto-join eligibility | Notifications |
| Appearance | status bar title/icon, menu display, event visibility | StatusBar + Calendar |
| Advanced | scripts, custom event filters, debug-only controls | Settings + Notifications |
| Status | diagnostics, provider health, export report | Diagnostics |

Implementation can remain a `TabView` on macOS 12. If the product separately
bumps to macOS 13, a sidebar shell can be considered, but the architecture
should not depend on `NavigationSplitView`.

The route model should be explicit:

```swift
enum PreferencesRoute: Hashable, Codable {
    case general
    case calendars
    case meetings
    case notifications
    case appearance
    case advanced
    case status
}
```

This lets `meetingbar://preferences` later support a route without coupling URL
handling to SwiftUI internals.

---

## Onboarding Flow

Onboarding should be short and setup-focused. It should collect only the
settings needed for MeetingBar to work reliably.

Recommended steps:

1. **Welcome**
   - Start the setup flow.
   - Do not duplicate marketing copy already available on the website.

2. **Calendar Access**
   - Choose calendar provider.
   - Request EventKit permission or start Google sign-in.
   - Show clear denied/error/retry states.

3. **Calendar Selection**
   - Select calendars from the chosen provider.
   - Reuse `CalendarSelectionList`.
   - Preserve the ability to continue with all calendars when appropriate.

4. **Meeting Defaults**
   - Choose default browser/open target.
   - Optionally choose a create-meeting action.
   - Reuse provider registry components.

5. **Notifications**
   - Request notification permission only when explaining why it is needed.
   - Configure basic reminder defaults.
   - Keep advanced automation out of onboarding.

6. **Ready**
   - Mark onboarding complete.
   - Trigger initial refresh/reconcile through `AppAction`.

The actual UI can combine adjacent steps if the screen becomes too long. The
state machine should still model them separately.

```swift
enum OnboardingStep: Hashable {
    case welcome
    case calendarAccess
    case calendarSelection
    case meetingDefaults
    case notifications
    case ready
}
```

Onboarding completion should not call `AppDelegate.setup()` manually. It should
emit an explicit action:

```swift
enum AppAction {
    case onboardingCompleted(OnboardingCompletion)
}
```

`AppModel` or a coordinator then persists settings, refreshes calendar data,
reconciles notifications, and opens the main status bar flow.

---

## Shared View Models

Avoid putting business logic in SwiftUI views. Use small models that translate
between feature state and controls.

Suggested models:

| Model | Responsibility |
|---|---|
| `PreferencesModel` | current route, settings bindings, save/apply/reset actions |
| `OnboardingModel` | setup step state, permission/auth progress, completion payload |
| `CalendarSettingsModel` | provider selection, permission state, calendar rows |
| `MeetingSettingsModel` | provider descriptors, opener preferences, bookmarks, create action |
| `NotificationSettingsModel` | notification permission, timing, fullscreen/auto-join toggles |
| `AppearanceSettingsModel` | status bar/menu/event visibility settings |
| `AdvancedSettingsModel` | scripts, regex validation, destructive/debug actions |
| `DiagnosticsModel` | provider health, refresh state, exportable diagnostics |

These models may be `ObservableObject` while the app supports macOS 12/13. Do
not require `@Observable` unless the app later targets macOS 14+.

---

## Provider-Driven Meetings UI

The meeting settings screen should be generated from registry metadata.

```text
MeetingProviderRegistry
  -> built-in descriptors
  -> custom descriptors from settings
  -> MeetingProviderSettingsList
```

Each provider row should be able to show:

- icon and display name;
- detected aliases, if useful for diagnostics;
- current open target or browser preference;
- whether create-meeting is supported;
- whether the provider has custom opener behavior;
- validation errors for custom regex/providers.

Provider settings should be stored by `MeetingProviderID`, not by one Defaults
key per provider.

Do not create a folder per simple provider. A folder is justified only when a
provider has custom opening, creation, auth, or parsing behavior.

---

## Calendar Provider UI

Calendar settings should tolerate provider-specific capabilities without
leaking provider implementation into unrelated views.

The UI should render a provider summary:

```swift
struct CalendarProviderDisplayState: Equatable {
    var provider: EventStoreProvider
    var title: String
    var status: ProviderHealth
    var supportsSignIn: Bool
    var supportsSignOut: Bool
    var permissionState: PermissionState
}
```

EventKit and Google can have different actions, but those actions should be
modeled as provider capabilities. `CalendarsTab` should not know AppAuth or
EventKit permission details.

Future Microsoft Graph work should fit by adding a provider adapter and display
metadata, not by rewriting Preferences.

---

## Notifications And Automation UI

The old split between notifications and advanced scripts is too implicit. The
new UI should make the responsibility split match the architecture:

- `Notifications`: user-facing notification timing and notification permission;
- `Actions`: fullscreen, auto-join, and script behavior that runs around event
  start;
- `Advanced`: script editing, regex filters, debug/test actions.

This does not necessarily require three separate routes. It does require the
view models to map to:

- `NotificationSettings`;
- `NotificationActionSettings`;
- `AdvancedSettings`.

Script test actions must run through an injected `ScriptRunner` / app action.
They should not inspect `AppDelegate.statusBarItem.events`.

---

## Diagnostics And Error States

Do the diagnostics work during the UI migration, not after.

Every major settings area should have an explicit error/loading/empty state:

- calendar permission denied;
- Google signed out or auth expired;
- provider refresh failed but stale events are preserved;
- no calendars selected;
- no meeting providers match a test URL;
- notification permission denied;
- script path missing or script execution failed.

`StatusSettingsView` should use `DiagnosticsModel` and a diagnostics exporter,
not raw `EventManager` and direct `Defaults`.

The same status components can be reused in onboarding for access failures.

---

## Visual And Interaction Guidelines

MeetingBar is a utility app. Preferences should feel quiet, compact, and
repeatable.

Guidelines:

- use consistent section headers and row spacing;
- avoid nested cards and marketing-style panels;
- prefer controls that match the value type:
  - toggles for booleans;
  - pickers or menus for enum values;
  - steppers/sliders/text fields for numeric values;
  - table/list rows for calendars and providers;
  - icon buttons only where the icon is familiar and has a tooltip;
- keep rows resilient to long localized text;
- avoid fixed-width labels except behind a shared row component;
- support keyboard navigation and VoiceOver labels;
- show inline validation where the user can fix the value;
- keep dangerous actions separated and confirmed.

The redesign should not add many new settings. It should make existing settings
easier to understand and make future provider additions cheaper.

---

## Testing Strategy

The UI migration should increase testability even if SwiftUI view line coverage
remains modest.

Coverage targets:

| Area | Target | Notes |
|---|---:|---|
| Settings snapshots and migrations | 95% | old Defaults keys, new grouped settings |
| Preferences view models | 90% | bindings, validation, route changes, action emission |
| Onboarding model | 90-95% | step transitions, retry/error states, completion |
| Calendar settings model | 90% | provider capabilities, selected calendars, health states |
| Meeting settings model | 90-95% | registry rendering, provider preferences, bookmarks |
| Notification settings model | 90% | permission states, timing, action settings |
| SwiftUI views | smoke/host tests | verify critical rendering states; do not chase 95% line coverage |

Tests to add:

- preferences route persists/restores if supported;
- changing a setting emits one settings update and one app action;
- old meeting browser keys migrate to provider preference map;
- bookmark rows render provider IDs and migrate old enum values;
- provider list renders a new descriptor without editing the view;
- calendar provider switch emits provider-change action;
- denied calendar access shows retry/system-settings action;
- onboarding cannot complete before required access/selection state;
- onboarding completion writes settings and triggers refresh/reconcile actions;
- script test action goes through a fake runner;
- diagnostics export uses model state, not global Defaults.

Manual QA before release:

- English plus at least two long-localized languages;
- first launch onboarding with EventKit allowed/denied;
- Google sign-in success/failure/cancel;
- provider switch after onboarding;
- notification permission allowed/denied;
- custom regex validation;
- keyboard-only navigation;
- VoiceOver labels for provider rows and destructive actions.

Do not add a third-party snapshot testing dependency just to support this
redesign. Prefer model tests, host-app smoke tests, and manual QA unless a
snapshot tool proves its value in a separate PR.

---

## Migration Sequence

Do not redesign the visible UI first. Migrate the boundaries underneath, then
replace screens in slices.

1. **Characterize current settings behavior**
   - Cover current Defaults snapshots, bookmarks, browser preferences,
     onboarding completion, and calendar selection behavior.

2. **Introduce `Settings/` boundary**
   - Move `AppSettings`, `SettingsStore`, and migration logic into `Settings/`.
   - Add temporary binding adapters for existing Preferences screens.

3. **Extract shared settings components**
   - Add `SettingsSection`, `SettingsRow`, inline message, and validation
     primitives.
   - Do not change product behavior yet.

4. **Migrate calendar settings UI**
   - Replace `CalendarsTab(eventManager:)` with `CalendarSettingsView`.
   - Route provider and calendar selection through settings/app actions.

5. **Migrate meeting settings UI**
   - Replace hard-coded `LinksTab` provider rows with registry-driven rows.
   - Migrate bookmarks and create-meeting choices to provider IDs/actions.

6. **Migrate notification and automation settings**
   - Separate notification timing from in-app action settings.
   - Route script test/run actions through injected services.

7. **Replace onboarding internals**
   - Add `OnboardingModel` and state machine.
   - Reuse calendar, meeting, and notification components.
   - Remove `AppDelegate`/`EventManager` reach-through.

8. **Visual consistency pass**
   - Apply consistent spacing, labels, row widths, inline messages, and
     accessibility labels.
   - Run long-localization and small-window QA.

9. **Remove temporary adapters**
   - Delete old direct Defaults UI paths and deprecated wrappers.
   - Update docs and screenshots if needed.

---

## Work To Do Now To Avoid Redesigning Twice

These should be included in the 5.0 architecture/UI migration because deferring
them would force another Preferences/Onboarding rewrite.

### Settings Migration Versioning

Add explicit settings migration tests and a migration version. Meeting provider
IDs, browser preference maps, bookmarks, and onboarding completion must survive
the migration.

### Permission And Auth State Model

Represent EventKit permission, Google auth, and notification permission as
display states. Do not let individual views rediscover permission state
independently.

### Provider Capability Metadata

Calendar and meeting providers need display metadata and capabilities before
the UI is rebuilt. Otherwise the UI will hard-code provider differences again.

### Shared Diagnostics Surface

Provider health and diagnostics should have one model used by Status
Preferences, onboarding access errors, and issue-report export.

### Localization Pass

The UI redesign will touch many strings. Do one localization-key pass during
the migration and test long strings before release.

### Accessibility Baseline

Set keyboard navigation, focus order, labels, and destructive action
confirmation during the redesign. Retrofitting accessibility later usually
changes layout again.

### Script And Automation Safety

Advanced script controls should use injected runners, show validation, and avoid
global app-state reach-through. This affects both architecture and UI.

### Platform Target Decision

Decide macOS 12 vs 13 before choosing the final Preferences shell. The target
does not block the architecture, but it affects whether `NavigationSplitView`
is available. Do not adopt macOS 14-only Observation for this work.

### Release Documentation

If screenshots, onboarding copy, or help text exist outside the app, update them
in the same release branch. The migration changes how users discover settings.

---

## Non-Goals

Do not include these in the UI migration:

- replacing the menu bar with `MenuBarExtra`;
- a full app visual rebrand;
- adding many new preferences;
- Microsoft Graph provider UI before the provider architecture exists;
- runtime plugin management UI;
- switching the app to SwiftUI lifecycle;
- adding a broad snapshot-testing dependency without a separate justification.

---

## Definition Of Done

The Preferences/Onboarding migration is done when:

- Preferences no longer read feature settings directly from `Defaults`;
- onboarding no longer reaches into `AppDelegate` or creates `EventManager`;
- calendar provider UI is capability-driven;
- meeting provider UI is registry-driven;
- adding a simple meeting provider updates the settings UI automatically;
- scripts and diagnostics use injected services/models;
- onboarding and preferences share calendar, meeting, and notification
  components;
- long localized text, keyboard navigation, and VoiceOver labels have been
  manually checked;
- old settings, bookmarks, provider choices, and onboarding completion migrate
  safely;
- tests cover settings/view-model logic at the agreed targets.
