# MeetingBar Architecture Migration Plan

Status: proposed execution plan for [`ARCHITECTURE_UPDATE.md`](ARCHITECTURE_UPDATE.md).

This document turns the target architecture into a sequence of reviewable PRs.
It is deliberately more operational than the architecture update: it says what
to test, what to move, what code to reshape, and when the migration is complete.

The Preferences/Onboarding UI migration is tracked in
[`PREFERENCES_ONBOARDING_REDESIGN_PLAN.md`](PREFERENCES_ONBOARDING_REDESIGN_PLAN.md).

The guiding rule: do not move code first. Add characterization tests, extract a
clear boundary, then move files when ownership is already obvious.

---

## Success Criteria

The migration succeeds only if all of these are true:

- common feature work maps to one top-level feature folder;
- the app remains one shipping Xcode target while the hostless SwiftPM logic
  package remains available for fast tests;
- `AppDelegate` is a composition root, not a behavior owner;
- `AppModel` owns app state and receives explicit `AppAction`s;
- `Defaults` reads are isolated in `Settings/SettingsStore` and migration
  adapters;
- Preferences and Onboarding use shared settings/provider components instead of
  direct `Defaults`, `EventManager`, or `AppDelegate` reach-through;
- status bar, menu, and notification state are derived from the same `AppState`;
- EventKit, Google Calendar, and future calendar providers are separate
  adapters behind `CalendarRepository`;
- meeting providers are registry entries, not scattered enum/switch edits;
- notification planning, scheduling, in-app actions, and UN delegate handling
  are separate components;
- simple meeting provider additions require descriptor + pattern + optional icon
  + tests;
- the pure/business-logic coverage target reaches 90-95%;
- high-risk AppKit/OS glue has characterization tests even if line coverage is
  lower.

---

## Coverage Strategy

The 90-95% goal should apply to meaningful logic, not to every AppKit line. The
app contains OS adapters that are hard to cover by line count and not worth
contorting for coverage. Measure and enforce coverage by layer.

### Coverage Targets

| Area | Target | Notes |
|---|---:|---|
| Pure domain logic | 95% | filtering, selection, status presentation, meeting detection, notification planning |
| Meeting provider registry/opening | 90-95% | descriptors, pattern matching, migration, custom opener fallback paths |
| Calendar mapping/repository | 90% | provider selection, preservation on failure, EventKit/Google mappers/parsers |
| AppModel reducers/actions | 90-95% | state transitions and effect scheduling through fakes |
| Notification scheduler/action scheduler/action runner | 90% | diffing, identity stability, processed record behavior, due actions |
| Settings migration | 95% | all persisted setting migrations and compatibility decoding |
| Preferences and onboarding models | 90-95% | settings bindings, route changes, setup step transitions, action emission |
| AppKit renderers/controllers | characterization | verify key states; do not chase 95% line coverage |
| Window/URL/lifecycle adapters | characterization | verify action forwarding and delegate wiring |

Overall Xcode target coverage may remain below 90 because AppKit/SwiftUI views
and OS callbacks are not the main risk. The gate should be feature-aware.

The coverage plan depends on keeping a test-only SwiftPM package for pure logic.
That package is not a separate product architecture. It is a fast test harness.
As files move from `Core/Policies` into feature folders, `Package.swift` must be
updated in the same PR or an adjacent PR so hostless coverage continues to
measure the migrated pure logic.

### Coverage Gates To Add

Add or evolve Makefile targets during Phase 1:

```text
make test-logic
make test
make coverage-logic-report
make coverage-app-report
make coverage-gate
```

`coverage-gate` should fail CI when:

- hostless logic coverage drops below the agreed threshold;
- any migrated feature folder falls below its threshold;
- a high-risk file is changed without a matching test file change, unless the PR
  explicitly explains why no behavior changed.

Start with reporting-only thresholds for one or two PRs, then make them
blocking once the baseline is stable.

### Test Harnesses To Build

Before major refactors, add test helpers:

- `FakeClock` or injectable `now`;
- `FakeSettingsStore`;
- `FakeCalendarRepository`;
- `FakeEventStore`;
- `FakeNotificationRequestSink`;
- `FakeNotificationRecordStore`;
- `FakeMeetingProviderOpener`;
- `FakeURLRunner` / `FakeBrowserOpener`;
- `FakeScriptRunner`;
- `FakeWindowCoordinator`;
- `AppModelTestHarness` that records effects and published state.

These fakes are part of the migration, not optional cleanup. They prevent the
new architecture from becoming harder to test than the old one.

---

## Migration Rules

Use these rules in every PR:

1. Add characterization tests before changing behavior or moving ownership.
2. Preserve public behavior unless the PR says otherwise.
3. Keep file moves separate from logic changes when possible.
4. Keep compatibility adapters for old persisted settings.
5. Do not introduce a new abstraction unless it removes a real dependency or
   collapses repeated switch/defaults logic.
6. Do not move `NSStatusItem`, `NSMenuItem`, `UNUserNotificationCenter`,
   EventKit, AppAuth, Keychain, AppleScript, or URL opening into pure logic.
7. Each PR should leave the app buildable and shippable.

---

## Phase 0: Baseline and Inventory

Goal: know what is currently protected and what must be characterized before
moving code.

PRs:

1. **Coverage baseline report**
   - Run current `make test-logic` and `make test`.
   - Capture hostless and app-hosted coverage numbers in a short note or CI
     artifact.
   - Identify uncovered high-risk files.

2. **Risk matrix**
   - Map each high-risk file to target owner:
     - `AppDelegate` -> `AppModel`, `WindowCoordinator`, `URLHandler`,
       `LifecycleObserver`, `NotificationCenterDelegate`;
     - `EventManager` -> `CalendarRepository` / `EventRefreshService`;
     - `StatusBarItemController` -> `StatusBarController` + presentation/menu
       state;
     - `MenuBuilder` -> `StatusBarMenuBuilder`;
     - `NotificationScheduler` -> planner/scheduler/action scheduler/action runner/record store;
     - `MeetingServices` -> meeting provider registry;
     - `Preferences/*` and `Onboarding/*` -> `Settings/Preferences`,
       `Settings/Onboarding`, and shared settings components.

3. **Characterization test backlog**
   - File issues or checklist items for missing tests:
     - meeting opener fallback paths;
     - current bookmark/create-meeting decoding;
     - lifecycle wake/unlock refresh behavior;
     - status bar menu states;
     - notification processed-record behavior.

Exit criteria:

- current coverage is known;
- every later phase has a test backlog;
- `ROADMAP.md`, `ARCHITECTURE_UPDATE.md`, and this plan agree on `MenuBarExtra`,
  `Observation`, macOS target policy, and the test-only SwiftPM package;
- no production code behavior changed.

---

## Phase 1: Test Infrastructure and Coverage Gates

Goal: make the rest of the migration safe.

Code changes:

- add coverage gate scripts or Makefile targets;
- expand `LOGIC_COVERAGE_SOURCES` from `MeetingBar/Core/Policies` to the
  migrated pure feature folders as they appear;
- update `Package.swift` so the hostless `MeetingBarLogic` package can include
  pure files after they move out of `Core/Policies`;
- add shared test fixtures for events, calendars, settings, providers, and
  notification plans;
- add fake side-effect services.

Tests to add:

- tests for the fakes themselves only when they contain logic;
- sample `AppModelTestHarness` test proving state/effect assertions are easy;
- CI/Makefile smoke test for coverage reporting.
- one sample Preferences or Onboarding model test proving UI logic can be
  tested without launching the full app.

Coverage gate:

- reporting-only initially;
- after two stable PRs, enforce 90%+ on the current hostless pure logic set.

Exit criteria:

- contributors can run one command and see coverage;
- future phases can add feature-specific thresholds;
- no architecture migration starts without test harness support.

---

## Phase 2: Settings Boundary

Goal: remove hidden `Defaults` reads from feature logic.

New target shape:

```text
Settings/
  AppSettings.swift
  SettingsStore.swift
  SettingsMigration.swift
  SettingsBindingAdapter.swift
```

Code changes:

- introduce `AppSettings` grouped by feature:
  - `CalendarSettings`;
  - `EventDisplaySettings`;
  - `StatusBarSettings`;
  - `StatusBarMenuSettings`;
  - `NotificationSettings`;
  - `MeetingSettings`;
  - `AdvancedSettings`;
- introduce `SettingsStore` as the only owner of `Defaults` reads/writes for
  app logic;
- introduce explicit settings migration/versioning for provider IDs, bookmarks,
  browser preference maps, and onboarding completion;
- keep SwiftUI Preferences on `@Default` temporarily if needed, but make them
  feed the store and model through settings-change actions;
- replace scattered `.current` settings factories gradually;
- keep compatibility with existing keys.

Preferences migration:

- phase in small preferences view models or bindings backed by `SettingsStore`;
- allow `@Default` only as a temporary Preferences UI implementation detail;
- start moving common Preferences/Onboarding controls into
  `Settings/Components`;
- remove direct `@Default` from non-Preferences code during this phase;
- final state allows direct `Defaults` only in `SettingsStore`, migration
  adapters, and any explicitly documented UI-only binding layer.

High-value removals:

- `NotificationPlanningSettings.currentForScheduler`;
- `StatusBarPresentationSettings.current`;
- `StatusBarTitleSettings.current`;
- direct meeting opener reads of browser settings;
- status/menu direct `Defaults` reads where a state snapshot is available.

Tests to add:

- `AppSettings` snapshot defaults;
- settings change publisher emits grouped snapshots;
- each old settings key maps to the same new snapshot value;
- no regression for language, hidden title, notification toggles, selected
  calendars, dismissed events, provider choice.

Coverage target:

- 95% for settings snapshot/migration logic.

Exit criteria:

- pure logic no longer needs `Defaults`;
- settings can be injected in tests;
- no user-facing setting changes.

---

## Phase 3: Meeting Provider Registry

Goal: make adding meeting providers simple and safe.

New target shape:

```text
Meetings/
  Domain/
  Providers/
  Detection/
  Opening/
  Creation/
```

Code changes:

- add `MeetingProviderID` stable string identity;
- add `MeetingProviderDescriptor`;
- add `MeetingProviderRegistry`;
- add provider aliases and detection priority so specific providers beat generic
  patterns and provider variants can share behavior;
- move built-in regex patterns into descriptors;
- convert icon lookup from switch to descriptor metadata;
- convert open behavior from one large switch into opener strategies;
- convert create-meeting choices into `CreateMeetingAction`s;
- add `MeetingOpenPreferences` map keyed by `MeetingProviderID`;
- add compatibility layer for existing `MeetingServices`, bookmarks, browser
  keys, and create-meeting setting;
- keep old API wrappers temporarily:
  - `detectMeetingLink(...)`;
  - `openMeetingURL(...)`;
  - `getIconForMeetingService(...)`;
  - old bookmark decoding.

Provider registry requirements:

- built-in provider IDs are stable strings;
- custom provider IDs use a reserved namespace such as `custom:<uuid>`;
- generic "any link" detection, if kept, has the lowest priority;
- provider aliases cover variants such as `zoomgov`, `zoom_native`, and
  `meet_stream` without forcing duplicated settings and icons;
- use one opening abstraction: `MeetingOpenStrategy`, with custom strategies
  implemented through `MeetingProviderOpener`.

Suggested PR slices:

1. Provider ID + descriptor + registry with no behavior change.
2. Detection uses registry but old `MeetingServices` still exists.
3. Icon lookup uses descriptor metadata.
4. Opening strategies replace the switch.
5. Create-meeting registry replaces `CreateMeetingServices`.
6. Settings/bookmark migration.
7. Remove deprecated wrappers after callers migrate.

Tests to add before replacement:

- one test per built-in regex pattern group;
- source priority still wins:
  `providerConferenceData > eventURL > location > notes > strippedHTMLNotes > customRegex`;
- longer URL still wins within a source;
- Google Meet `authuser` normalization;
- Outlook Safe Links cleanup;
- HTML notes extraction;
- Zoom web -> app scheme -> fallback;
- Zoom native -> browser fallback;
- Teams app scheme fallback;
- Slack huddle deep link;
- Riverside two-scheme fallback;
- FaceTime, phone, generic browser behavior;
- create-meeting action selection and custom URL validation;
- bookmark decode from old enum and new provider ID;
- browser preference migration from old per-provider keys to map.

Coverage target:

- 95% detection/ranking;
- 90-95% opener strategies;
- 95% settings/bookmark migration.

Exit criteria:

- adding a simple provider is descriptor-only plus tests;
- complex providers add a custom opener in `Meetings/Providers/Openers`;
- no new app-wide switch is needed for ordinary provider behavior.

---

## Phase 4: Calendar Provider Separation

Goal: make calendar providers independently navigable and ready for future
Microsoft Graph work.

New target shape:

```text
Calendar/
  Domain/
  Providers/EventKit/
  Providers/Google/
  CalendarRepository.swift
```

Code changes:

- split `EventStore` from `AuthenticatedEventStore`;
- remove `@MainActor` from the base `EventStore` contract;
- rename provider files:
  - `EKEventStore` -> `EventKitEventStore`;
  - `GCEventStore` -> `GoogleCalendarEventStore`;
- extract mappers/parsers:
  - EventKit event/calendar mapper;
  - Google JSON parser;
- extract provider-specific auth/API concerns:
  - `GoogleCalendarAuth`;
  - `GoogleCalendarAPI`;
  - `EventKitPermissions`;
- add `CalendarRepository` as the only active-provider selector;
- move refresh preservation logic out of `EventManager`;
- move selected calendar and date range calculation behind repository/service
  inputs.

Actor-isolation requirements:

- `CalendarRepository` may be `@MainActor` because it publishes app state;
- provider fetch APIs should not be globally main-actor isolated;
- EventKit enumeration must remain off-main;
- auth methods that present UI or touch AppAuth external-user-agent state may be
  `@MainActor` on the authenticated-provider side.

Suggested PR slices:

1. Protocol split with adapters and tests.
2. `CalendarRepository` introduced while `EventManager` still calls it.
3. EventKit folder extraction.
4. Google folder extraction.
5. Event refresh service replaces `EventManager` fetch internals.
6. Remove provider-specific calls from UI/Preferences.

Tests to add:

- EventKit no longer stubs sign-in/sign-out;
- provider switching clears selected calendars and signs out only authenticated
  providers when requested;
- refresh preserves last known calendars/events on failure;
- provider health transitions:
  - success;
  - auth required;
  - stale network failure;
  - partial Google calendar failure;
- selected-calendar filtering;
- today vs today-and-tomorrow range;
- EventKit mapper handles missing/unknown calendar safely;
- Google parser covers all-day, timed, canceled, tentative, attendees,
  conference data, HTML notes, per-calendar errors.

Coverage target:

- 90% repository/refresh logic;
- 90% provider mappers/parsers;
- characterization tests for real EventKit/AppAuth boundaries.

Exit criteria:

- status bar, notifications, and preferences do not know whether the active
  provider is EventKit or Google except through `EventStoreProvider`;
- adding Microsoft Graph means adding a provider folder and repository case, not
  touching unrelated features.

---

## Phase 5: Notifications Split

Goal: make notification behavior deterministic and testable.

New target shape:

```text
Notifications/
  NotificationPlanner.swift
  NotificationScheduler.swift
  NotificationActionScheduler.swift
  NotificationActionRunner.swift
  NotificationCenterDelegate.swift
  NotificationContentFactory.swift
  NotificationRecordStore.swift
```

Code changes:

- rename `NotificationPlanningPolicy` to `NotificationPlanner`;
- keep pure plan generation separate from system scheduling;
- extract `NotificationContentFactory`;
- extract `NotificationRecordStore` for processed event records;
- extract `NotificationActionScheduler` if in-app actions still need delayed
  tasks independent of system notification requests;
- extract `NotificationActionRunner` for fullscreen, auto-join, and script;
- make `NotificationCenterDelegate` translate UN responses to `AppAction`s;
- remove action decisions from scheduler;
- ensure wake/unlock/timezone/day-change reconcile through app actions.

Responsibility split:

- `NotificationPlanner`: pure desired plans;
- `NotificationScheduler`: system notification request reconciliation only;
- `NotificationActionScheduler`: schedules due in-app action tasks if needed;
- `NotificationActionRunner`: executes fullscreen, auto-join, and scripts;
- `NotificationRecordStore`: owns processed-record persistence.

Suggested PR slices:

1. Content factory extraction.
2. Record store extraction.
3. Action runner extraction.
4. Scheduler becomes request reconciler only.
5. UN delegate adapter sends actions.
6. Remove obsolete legacy notification helpers.

Tests to add:

- notification plan identities are stable;
- event start/end requests are diffed idempotently;
- stale requests are removed;
- content changes replace pending requests;
- hidden title changes notification content;
- snooze flow remains compatible;
- fullscreen action fires once and records only after successful side effect;
- auto-join requires meeting link when configured;
- script action can run without meeting link;
- screen lock blocks in-app side effects without marking them processed;
- wake/unlock/time changes reconcile current plans.

Coverage target:

- 95% planner;
- 90% scheduler diff/content factory/record store/action runner.

Exit criteria:

- scheduler has no direct fullscreen/auto-join/script policy decisions;
- all notification side effects are behind injectable services;
- no direct `Defaults` reads remain inside notification logic.

---

## Phase 6: AppModel and Unidirectional Actions

Goal: centralize app state without creating a new god object.

New target shape:

```text
App/
  AppModel.swift
  AppState.swift
  AppAction.swift
  AppEnvironment.swift
```

Code changes:

- introduce `AppState`;
- introduce `AppAction`;
- introduce `AppEnvironment`;
- wire settings, calendar refresh, notifications, status bar, lifecycle, and
  windows through actions;
- move Combine subscriptions out of `AppDelegate` and feature controllers;
- make refresh, settings change, wake, unlock, timezone, day change, and
  notification response explicit actions;
- keep feature services responsible for feature logic.

`AppModel` guardrails:

- no imports of AppKit, EventKit, UserNotifications, AppAuth, Keychain, or
  AppleScript;
- no direct `Defaults` reads;
- no feature-specific implementations that belong in feature services;
- use fakeable clients/protocols/closures in `AppEnvironment`.

Suggested PR slices:

1. `AppState` and derived state with tests, no wiring.
2. `AppModel.send` handles refresh actions through fake environment.
3. Settings changes flow through `AppModel`.
4. Notification reconcile actions flow through `AppModel`.
5. Lifecycle actions flow through `AppModel`.
6. AppDelegate uses model while old controllers still exist.

Tests to add:

- launched -> initial settings load -> initial refresh request;
- settings change updates derived status/notification state;
- refresh success updates calendars/events/health;
- refresh failure preserves last known events;
- provider change clears selected calendars and triggers refresh;
- wake/unlock/timezone/day-change trigger refresh/reconcile;
- notification response maps to join/dismiss/snooze actions;
- screen lock blocks in-app actions;
- manual refresh action does not duplicate fetches.

Coverage target:

- 90-95% `AppModel` action handling.

Exit criteria:

- `AppDelegate` no longer owns behavior pipelines;
- state transitions are testable without AppKit;
- feature renderers receive derived state.

---

## Phase 7: Status Bar Renderer and Menu State

Goal: make the menu bar a renderer of app state.

New target shape:

```text
StatusBar/
  StatusBarController.swift
  StatusBarPresentation.swift
  StatusBarMenuState.swift
  StatusBarMenuBuilder.swift
  StatusBarTitleRenderer.swift
```

Code changes:

- create `StatusBarMenuState` from `AppState`;
- move menu decisions out of `MenuBuilder` into state/presentation builders
  where possible;
- make `StatusBarMenuBuilder` build from state, not `Defaults`;
- make `StatusBarController` own only `NSStatusItem` and rendering;
- remove `events` from status bar controller;
- replace direct target actions with an action handler that sends `AppAction`s;
- remove global `shortenTitle` / `createEventStatusString` wrappers.

Suggested PR slices:

1. Add `StatusBarMenuState` and tests.
2. Menu builder consumes menu state.
3. Status bar controller consumes presentation/menu state.
4. Actions route through `AppAction`.
5. Remove old event/defaults dependencies.

Tests to add:

- no calendars state;
- no events state;
- today and tomorrow sections;
- timeline visible/hidden;
- bookmarks collapsed/expanded;
- alternate meeting links;
- dismissed/undismissed menu items;
- pending/tentative/declined/personal/past styling decisions;
- long status title compact fallback;
- hidden title;
- stacked title;
- no meeting link icon fallback;
- right-click join action maps to app action.

Coverage target:

- 90% status presentation/menu-state logic;
- characterization tests for AppKit rendering.

Exit criteria:

- `StatusBarController` does not read settings, store events, compute next
  event, or reconcile notifications directly;
- menu actions are testable as action mapping.

---

## Phase 8: Preferences and Onboarding UI Migration

Goal: make settings UI use the new architecture instead of direct persistence
and app-lifecycle reach-through.

Detailed UI plan:
[`PREFERENCES_ONBOARDING_REDESIGN_PLAN.md`](PREFERENCES_ONBOARDING_REDESIGN_PLAN.md).

New target shape:

```text
Settings/
  Components/
  Preferences/
  Onboarding/
```

Code changes:

- move Preferences and Onboarding under `Settings/`;
- introduce `PreferencesModel`, `PreferencesRoute`, `OnboardingModel`, and
  `OnboardingStep`;
- replace direct `@Default` / `Defaults[...]` usage with `SettingsStore`
  bindings or view models;
- replace `CalendarsTab(eventManager:)` with a calendar settings component that
  sends provider/calendar actions;
- replace hard-coded `LinksTab` provider rows with registry-driven meeting
  provider settings;
- route script test/run actions through injected runners or app actions;
- make onboarding completion emit an explicit app action instead of calling
  `AppDelegate.setup()` or creating `EventManager`;
- add consistent settings row/section components and inline validation/error
  states.

Suggested PR slices:

1. Shared settings row/section components with no behavior change.
2. Preferences route/model skeleton backed by `SettingsStore`.
3. Calendar settings view migration.
4. Meeting settings view migration.
5. Notification/automation/advanced settings view migration.
6. Onboarding model/state-machine migration.
7. Visual consistency, accessibility, and long-localization pass.
8. Remove temporary Defaults binding adapters.

Tests to add:

- preferences route and settings binding behavior;
- one setting change emits one settings update and expected app action;
- provider list renders a newly registered meeting descriptor without editing
  the view;
- calendar provider switch emits provider-change action;
- calendar access denied/error states render actionable retry/system-settings
  paths;
- onboarding step transitions, retry states, and completion payload;
- onboarding completion triggers settings persistence, refresh, and notification
  reconcile actions through fakes;
- script test action uses a fake runner;
- diagnostics export uses model state.

Coverage target:

- 90-95% for Preferences and Onboarding view models;
- host/smoke coverage for critical SwiftUI rendering states;
- manual QA for long localized strings, keyboard navigation, VoiceOver labels,
  and permission/auth flows.

Exit criteria:

- Preferences no longer own feature persistence;
- Onboarding no longer reaches into `AppDelegate` or creates `EventManager`;
- calendar and meeting settings UI are provider/capability driven;
- Preferences and Onboarding share calendar, meeting, notification, and
  diagnostics components.

---

## Phase 9: Coordinators and AppDelegate Reduction

Goal: finish moving OS integration to named adapters.

New target shape:

```text
Windows/
  WindowCoordinator.swift
  URLHandler.swift
  LifecycleObserver.swift

Notifications/
  NotificationCenterDelegate.swift
```

Code changes:

- move onboarding/preferences/changelog/fullscreen windows to
  `WindowCoordinator`;
- move `meetingbar://` and OAuth callback handling to `URLHandler`;
- move screen lock/unlock/wake/timezone/day observers to `LifecycleObserver`;
- move UN delegate methods to `NotificationCenterDelegate`;
- keep `AppDelegate` responsible only for creation and wiring.

Tests to add:

- URL `meetingbar://preferences` emits open preferences action;
- OAuth callback forwards non-preferences URLs;
- wake/unlock/timezone/day-change emit expected actions;
- closing onboarding before completion terminates or emits termination request;
- closing changelog records revision and refreshes menu state;
- fullscreen window request uses expected event;
- notification response emits join/dismiss/snooze actions.

Coverage target:

- characterization coverage, not 95% line coverage.

Exit criteria:

- `AppDelegate` is small enough to understand without reading feature behavior;
- OS callbacks are adapters, not business logic.

---

## Phase 10: File Layout and Naming Cleanup

Goal: make the physical project match the architecture.

Code changes:

- move files into final feature folders;
- update Xcode project references in small batches;
- remove obsolete `Core/Policies`, `Core/Services`, `Core/Managers`, and
  root `Services` once empty;
- rename `Policy` suffixes when the new name is clearer:
  - `EventSelectionPolicy` + `EventFilterPolicy` -> `EventFiltering`;
  - `NotificationPlanningPolicy` -> `NotificationPlanner`;
  - `StatusBarPresentationPolicy` -> `StatusBarPresentation`;
  - `GoogleCalendarPolicy` can remain if it really classifies provider policy,
    or become `GoogleCalendarErrorClassifier`;
- update docs and AI-agent instructions.

Tests:

- no new behavior tests unless a move reveals missing coverage;
- run full suite after every project-file batch.

Coverage target:

- no coverage drop from previous phase.

Exit criteria:

- docs match code;
- old compatibility wrappers are removed or explicitly deprecated with removal
  timeline;
- file names are contributor-oriented.

---

## Phase 11: Hardening and Release Readiness

Goal: ship the architecture safely.

Tasks:

- run `make test`, `make test-logic`, `make lint`, `make validate-strings`;
- inspect coverage gates and address regressions;
- manually test:
  - EventKit provider;
  - Google provider;
  - provider switch;
  - wake/unlock;
  - notification scheduling;
  - fullscreen notification;
  - auto-join;
  - script on start;
  - meeting opening for Zoom, Teams, Meet, Slack, Riverside, generic link;
  - bookmarks;
  - create meeting;
  - preferences windows;
  - onboarding path;
- verify existing settings migrate on a copy of real defaults;
- update release notes with architecture and platform target implications.

Exit criteria:

- no known lost-settings migration bug;
- no major coverage gate exception remains;
- architecture docs describe current code, not future intent.

---

## Suggested PR Sequence

This is the preferred sequence. Split further if a PR becomes hard to review.

| PR | Theme | Main risk | Required tests |
|---:|---|---|---|
| 1 | Coverage baseline + gate reporting | CI churn | coverage command smoke |
| 2 | Package.swift logic-test strategy | hostless tests break after moves | SwiftPM package smoke |
| 3 | Test fakes/harnesses | test utility correctness | harness sample tests |
| 4 | `AppSettings` snapshot | settings regressions | defaults snapshot tests |
| 5 | SettingsStore publisher | missed updates | settings-change tests |
| 6 | Meeting provider descriptor/registry | duplicate identity | registry tests |
| 7 | Detection via registry | wrong link selection | detector parity tests |
| 8 | Meeting opener strategies | broken join | provider fallback tests |
| 9 | Create-meeting registry + migration | lost preference | migration tests |
| 10 | EventStore protocol split | provider switching | fake provider tests |
| 11 | CalendarRepository | stale/empty state | refresh preservation tests |
| 12 | EventKit provider folder | EventKit mapping | mapper tests |
| 13 | Google provider folder | OAuth/parser regressions | parser/API policy tests |
| 14 | Notification content/record store | request content drift | scheduler tests |
| 15 | Notification action scheduler/runner | duplicate actions | action tests |
| 16 | AppState/AppModel skeleton | new god object | reducer tests |
| 17 | AppModel refresh/settings flow | races | fake environment tests |
| 18 | AppModel lifecycle/notification flow | missed reconcile | action tests |
| 19 | StatusBarMenuState | menu regressions | state snapshot tests |
| 20 | StatusBar render-only controller | AppKit behavior | host tests |
| 21 | Settings UI shared components | layout churn | component smoke + localization checks |
| 22 | Preferences models and routes | settings drift | view-model tests |
| 23 | Calendar settings UI | provider selection regressions | model/action tests |
| 24 | Meeting settings UI | provider rows hard-coded again | registry/UI model tests |
| 25 | Notification/advanced settings UI | automation regressions | permission/action/script tests |
| 26 | Onboarding model and flow | broken first launch | state-machine tests |
| 27 | Preferences/onboarding visual QA | accessibility/layout regressions | host smoke + manual QA |
| 28 | Coordinators extraction | OS callback regressions | adapter tests |
| 29 | File moves/naming cleanup | project conflicts | full suite |
| 30 | Hardening/release | integration bugs | full suite + manual QA |

---

## Manual QA Matrix

Automated coverage is not enough for OS integrations. Run this matrix before
the architecture release:

| Area | Scenarios |
|---|---|
| Calendar providers | EventKit permission allowed/denied; Google signed in/out; provider switch; inaccessible Google calendar |
| Refresh | app launch; manual refresh; settings change; wake; unlock; timezone change; calendar day change |
| Status bar | no calendars; no events; next event; ongoing event; long title; hidden title; stacked time; icon-only fallback |
| Menu | today only; today+tomorrow; timeline; bookmarks; event details; alternate meeting links; dismissed events |
| Meetings | Meet authuser; Zoom app/browser fallback; Teams app/browser fallback; Slack huddle; Riverside schemes; generic URL; custom regex |
| Notifications | start; end; snooze; fullscreen; auto-join; script; screen locked; back-to-back events |
| Preferences/onboarding | first launch; route switching; long localized strings; keyboard navigation; VoiceOver labels |
| Settings migration | old bookmarks; old per-provider browsers; old create-meeting service; custom URL; onboarding completed |
| Windows/URLs | preferences URL; OAuth callback; onboarding close; changelog close; fullscreen window |

---

## Stop Conditions

Pause and reassess if any of these happen:

- a PR needs to touch more than three high-risk areas;
- a compatibility migration cannot be tested without real user data;
- coverage gates force tests that only assert implementation details;
- `AppModel` starts importing AppKit, EventKit, UserNotifications, AppAuth, or
  Keychain;
- `EventStore` fetch APIs become main-actor isolated and risk blocking the menu
  bar;
- Preferences or Onboarding start hard-coding provider-specific behavior that
  should come from provider descriptors/capabilities;
- a file move causes large Xcode project conflicts;
- a provider registry change makes simple providers harder to add than before.

The goal is a safer architecture, not architectural ceremony.
