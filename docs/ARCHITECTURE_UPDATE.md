# MeetingBar Architecture Update

Status: proposed target architecture for the next major architecture work.

This document describes the destination architecture, not the current code
layout. [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) remains the map of the code
as it exists today. This document should guide the migration plan, review
criteria, and future contributor-facing structure.

Execution plan: [`ARCHITECTURE_MIGRATION_PLAN.md`](ARCHITECTURE_MIGRATION_PLAN.md).
Preferences/onboarding UI plan:
[`PREFERENCES_ONBOARDING_REDESIGN_PLAN.md`](PREFERENCES_ONBOARDING_REDESIGN_PLAN.md).

If this document conflicts with current behavior, current behavior wins until a
small migration PR changes it with tests.

---

## Decision Summary

MeetingBar should move to a single-target, feature-sliced architecture with a
small unidirectional app model at the center.

The target shape:

- one Xcode app target for the shipping product;
- keep a test-only SwiftPM logic package for fast hostless tests, but do not
  introduce a separate shipped `MeetingBarCore` product in this migration;
- feature folders instead of layer folders such as `Core/Policies`,
  `Core/Services`, and `UI/StatusBar`;
- one `AppModel` as the source of truth for app state;
- explicit `AppAction`s for user actions and system events;
- `AppEnvironment` for side effects such as calendar refresh, notification
  scheduling, URL opening, scripts, windows, and settings persistence;
- a `Settings/` feature that owns `AppSettings`, `SettingsStore`,
  Preferences, Onboarding, and shared settings UI components;
- provider-specific calendar code isolated under `Calendar/Providers/...`;
- meeting services represented by a registry of provider descriptors, not by a
  large enum and scattered switch statements;
- AppKit remains the status bar shell. Do not replace `NSStatusItem` with
  `MenuBarExtra` as part of this architecture update.

This is intentionally not TCA, not MVVM everywhere, and not a plugin system. It
borrows the useful parts of unidirectional architecture: explicit state,
explicit actions, and side effects at the edges.

---

## Platform Decision

The architecture does not require a macOS deployment target bump.

A bump from macOS 12 to macOS 13 can be justified as a separate 5.0 platform
decision if the maintainer accepts the support tradeoff. It should not be used
as the reason for this architecture. In particular:

- `@Observable` is not a macOS 13 feature. Use `ObservableObject` for this
  architecture unless the app later bumps to macOS 14+.
- `MenuBarExtra` is not a good replacement for the current status bar behavior.
  MeetingBar needs `NSStatusItem`, attributed titles, custom menu items,
  hosted timeline views, and right-click behavior.
- A deployment target bump must be its own PR with release-note implications.

Recommended stance: the architecture should be written so it works with
`ObservableObject`. If 5.0 bumps to macOS 13, take the simplification where it
helps, but do not make the architecture dependent on macOS 14 Observation.

---

## Goals

The update should make the project easier to change and safer to maintain.

Primary goals:

- a new contributor can answer "where does this feature live?" quickly;
- app state is not spread across `AppDelegate`, `EventManager`,
  `StatusBarItemController`, `NotificationScheduler`, and `Defaults`;
- common behavior changes touch one feature area, not four layer folders;
- adding a calendar provider or meeting provider is straightforward;
- pure decisions stay easy to test;
- AppKit, EventKit, UserNotifications, Keychain, network, AppleScript, and URL
  opening stay at named boundaries.

Reliability goals:

- preserve last known good calendar data during provider failures;
- keep menu bar presentation, notifications, and menu contents derived from the
  same app state;
- make wake, unlock, timezone, day-change, settings-change, and provider-refresh
  behavior explicit actions;
- avoid hidden `Defaults` reads inside deep logic.

Contributor goals:

- new simple meeting providers should not require edits to many switches;
- calendar provider implementation details should not leak into status bar,
  notification, or preferences code;
- Preferences and Onboarding should share provider/settings components instead
  of duplicating setup decisions;
- file names should describe product concepts, not architecture jargon.

---

## Non-Goals

Do not include these in the architecture migration:

- a separate `MeetingBarCore` SwiftPM package;
- a full rewrite of the app lifecycle;
- replacing the menu bar implementation with SwiftUI `MenuBarExtra`;
- adding TCA or another dependency injection/state management framework;
- runtime-loaded plugins or bundle loading;
- broad UI redesign outside the Preferences/Onboarding architecture migration;
- new user-facing behavior unless required to preserve existing behavior during
  the migration.

---

## Target Data Flow

The target flow is:

```text
User actions / system events / settings changes / provider callbacks
        |
        v
AppModel.send(AppAction)
        |
        v
AppState mutation + async effects through AppEnvironment
        |
        v
Derived state:
  - selected calendars
  - filtered events
  - next event
  - status bar presentation
  - status bar menu state
  - notification plans
        |
        v
Coordinators and renderers:
  - StatusBarController
  - NotificationScheduler
  - WindowCoordinator
  - URLHandler
  - LifecycleObserver
```

The important rule is that UI and system adapters render or execute decisions.
They do not independently decide which event is next, which notifications should
exist, or which meeting link should win.

---

## Target Directory Layout

```text
MeetingBar/
+-- App/
|   +-- AppDelegate.swift
|   +-- AppModel.swift
|   +-- AppState.swift
|   +-- AppAction.swift
|   +-- AppEnvironment.swift
|
+-- Calendar/
|   +-- CalendarRepository.swift
|   +-- EventRefreshService.swift
|   +-- EventStore.swift
|   +-- AuthenticatedEventStore.swift
|   +-- EventStoreProvider.swift
|   |
|   +-- Domain/
|   |   +-- MBEvent.swift
|   |   +-- MBCalendar.swift
|   |   +-- ProviderHealth.swift
|   |   +-- EventFiltering.swift
|   |
|   +-- Providers/
|       +-- EventKit/
|       |   +-- EventKitEventStore.swift
|       |   +-- EventKitEventMapper.swift
|       |   +-- EventKitPermissions.swift
|       |
|       +-- Google/
|           +-- GoogleCalendarEventStore.swift
|           +-- GoogleCalendarAPI.swift
|           +-- GoogleCalendarAuth.swift
|           +-- GoogleCalendarParser.swift
|           +-- GoogleCalendarPolicy.swift
|
+-- Meetings/
|   +-- Domain/
|   |   +-- MeetingProviderID.swift
|   |   +-- MeetingLink.swift
|   |   +-- MeetingLinkCandidate.swift
|   |   +-- MeetingLinkSource.swift
|   |
|   +-- Providers/
|   |   +-- MeetingProviderDescriptor.swift
|   |   +-- MeetingProviderRegistry.swift
|   |   +-- BuiltInMeetingProviders.swift
|   |   +-- Openers/
|   |       +-- BrowserMeetingOpener.swift
|   |       +-- GoogleMeetMeetingOpener.swift
|   |       +-- ZoomMeetingOpener.swift
|   |       +-- TeamsMeetingOpener.swift
|   |       +-- SlackMeetingOpener.swift
|   |       +-- RiversideMeetingOpener.swift
|   |
|   +-- Detection/
|   |   +-- MeetingLinkDetector.swift
|   |   +-- MeetingLinkPattern.swift
|   |   +-- OutlookSafeLinkCleaner.swift
|   |   +-- HTMLMeetingTextExtractor.swift
|   |
|   +-- Opening/
|   |   +-- MeetingOpener.swift
|   |   +-- MeetingOpenContext.swift
|   |   +-- MeetingOpenPreference.swift
|   |
|   +-- Creation/
|       +-- MeetingCreator.swift
|       +-- CreateMeetingAction.swift
|       +-- CreateMeetingRegistry.swift
|
+-- Notifications/
|   +-- NotificationPlanner.swift
|   +-- NotificationScheduler.swift
|   +-- NotificationActionScheduler.swift
|   +-- NotificationActionRunner.swift
|   +-- NotificationCenterDelegate.swift
|   +-- NotificationContentFactory.swift
|   +-- NotificationRecordStore.swift
|
+-- StatusBar/
|   +-- StatusBarController.swift
|   +-- StatusBarPresentation.swift
|   +-- StatusBarMenuState.swift
|   +-- StatusBarMenuBuilder.swift
|   +-- StatusBarTitleRenderer.swift
|   +-- DiagnosticsReport.swift
|
+-- Windows/
|   +-- WindowCoordinator.swift
|   +-- LifecycleObserver.swift
|   +-- URLHandler.swift
|
+-- Settings/
|   +-- AppSettings.swift
|   +-- SettingsStore.swift
|   +-- SettingsMigration.swift
|   +-- SettingsBindingAdapter.swift
|   |
|   +-- Components/
|   |   +-- SettingsSection.swift
|   |   +-- SettingsRow.swift
|   |   +-- CalendarProviderPicker.swift
|   |   +-- CalendarSelectionList.swift
|   |   +-- MeetingProviderSettingsList.swift
|   |   +-- NotificationTimingControls.swift
|   |   +-- DiagnosticsPanel.swift
|   |
|   +-- Preferences/
|   |   +-- PreferencesView.swift
|   |   +-- PreferencesModel.swift
|   |   +-- PreferencesRoute.swift
|   |
|   +-- Onboarding/
|       +-- OnboardingView.swift
|       +-- OnboardingModel.swift
|       +-- OnboardingStep.swift
|
+-- Support/
    +-- Scripts.swift
    +-- Keychain.swift
    +-- Constants.swift
    +-- I18N.swift
    +-- Helpers.swift
```

Use subfolders when the feature has real internal boundaries. `Calendar` needs
`Providers` because EventKit and Google have different dependencies and failure
modes. `Meetings` needs `Providers` because new services must be easy to add.
Do not create deep folders for small features just to make the tree symmetrical.

---

## App Model

`AppModel` is the central state owner.

```swift
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AppState

    private let environment: AppEnvironment

    func send(_ action: AppAction) {
        // mutate state synchronously when possible
        // launch async effects through environment
        // feed effect results back as AppAction values
    }
}
```

`AppModel` is not a place to implement every feature. It owns state, action
dispatch, and effect coordination. Non-trivial feature logic must stay in
feature components such as `CalendarRepository`, `NotificationPlanner`,
`StatusBarPresentation`, `StatusBarMenuState`, and `MeetingOpener`.

Hard limits:

- no `AppKit`, `EventKit`, `UserNotifications`, `AppAuth`, `Keychain`, or
  AppleScript imports in `AppModel`;
- no direct `Defaults` reads in `AppModel`;
- no large feature-specific switch blocks beyond routing `AppAction`s;
- if an action needs more than a small state update, delegate to a feature
  service or pure builder.

`AppState` should contain raw state, not duplicated UI state:

- `settings: AppSettings`
- `calendars: [MBCalendar]`
- `events: [MBEvent]`
- `providerHealth: ProviderHealth`
- `screenIsLocked: Bool`
- `now: Date`
- small transient state required to avoid duplicate effects.

Derived state should be computed from `AppState`:

- `selectedCalendars`
- `filteredEvents`
- `nextEvent`
- `statusBarPresentation`
- `statusBarMenuState`
- `notificationPlans`

`AppAction` should name things that happen:

- `launched`
- `settingsChanged(AppSettings)`
- `refreshRequested`
- `refreshCompleted(CalendarRefreshResult)`
- `providerChanged(EventStoreProvider)`
- `wakeDetected`
- `unlockDetected`
- `timeZoneChanged`
- `calendarDayChanged`
- `notificationResponseReceived(...)`
- `joinEventRequested(EventID)`
- `dismissEventRequested(EventID)`
- `openPreferencesRequested`
- `quitRequested`

This makes wake/unlock/settings behavior visible in one place instead of hidden
inside multiple observers and Combine sinks.

`AppEnvironment` owns side-effect dependencies:

```swift
struct AppEnvironment {
    var calendarRepository: CalendarRepositoryClient
    var settingsStore: SettingsStoreClient
    var notificationScheduler: NotificationSchedulerClient
    var notificationActionScheduler: NotificationActionSchedulerClient
    var notificationActionRunner: NotificationActionRunnerClient
    var meetingOpener: MeetingOpenerClient
    var meetingCreator: MeetingCreatorClient
    var clock: ClockClient
}
```

The names above are illustrative. The rule is what matters: use protocols or
closures at side-effect boundaries so `AppModel` can be tested with fakes. Avoid
introducing protocols for every small value type. Use protocols where the
boundary touches real I/O, provider implementation, OS integration, or durable
settings.

---

## Settings

`Defaults` should be read and written at one boundary: `SettingsStore`.
`SettingsStore`, `AppSettings`, settings migrations, Preferences, Onboarding,
and shared settings UI components should live under `Settings/`.

The rest of the app should consume immutable snapshots:

```swift
struct AppSettings: Equatable, Sendable {
    var calendar: CalendarSettings
    var events: EventDisplaySettings
    var statusBar: StatusBarSettings
    var menu: StatusBarMenuSettings
    var notifications: NotificationSettings
    var meetings: MeetingSettings
    var advanced: AdvancedSettings
}
```

Rules:

- pure logic receives settings structs, never `Defaults`;
- AppKit renderers receive already-derived state, not settings keys;
- settings changes are represented as `AppAction.settingsChanged`;
- Preferences should migrate to `SettingsStore` or small preferences view
  models. Temporary `@Default` usage is acceptable during migration only inside
  Preferences views, not in feature logic;
- Onboarding should use the same settings components and emit setup actions. It
  should not create `EventManager`, write `Defaults`, or call `AppDelegate`
  setup directly;
- new settings must be grouped by feature, not appended to a flat global list.

This does not require deleting the Defaults library. It changes where the
library is used.

Final state: direct `Defaults` / `@Default` usage is limited to `SettingsStore`,
settings migration adapters, and any narrow Preferences binding layer that is
explicitly documented as UI-only.

The Preferences and Onboarding UI migration is documented separately in
[`PREFERENCES_ONBOARDING_REDESIGN_PLAN.md`](PREFERENCES_ONBOARDING_REDESIGN_PLAN.md).

---

## Calendar Architecture

Calendar code should separate domain, repository orchestration, and provider
adapters.

```text
AppModel
  -> CalendarRepository
      -> EventStoreProvider selection
      -> EventKitEventStore
      -> GoogleCalendarEventStore
```

Base provider contract:

```swift
protocol EventStore: AnyObject, Sendable {
    func refreshSources() async
    func fetchAllCalendars() async throws -> [MBCalendar]
    func fetchEvents(for calendars: [MBCalendar], from: Date, to: Date) async throws -> [MBEvent]
}

protocol AuthenticatedEventStore: EventStore {
    @MainActor func signIn(forcePrompt: Bool) async throws
    @MainActor func signOut() async
}
```

EventKit should not stub OAuth methods. Google should not leak AppAuth or REST
details outside `Calendar/Providers/Google`.

Do not mark the base `EventStore` protocol as `@MainActor`. Provider fetches can
be slow and may need their own isolation. EventKit event enumeration in
particular must remain off the main actor so the menu bar does not hang on large
calendar stores. Put main-actor requirements only on auth/UI-facing methods that
actually need them.

Provider folders own provider-specific work:

- auth and permission checks;
- API request construction;
- JSON parsing;
- EventKit mapping;
- provider-specific error classification;
- provider-specific diagnostics input.

`CalendarRepository` owns:

- selecting the active provider from settings;
- switching providers;
- preserving last known good events on failure;
- publishing `ProviderHealth`;
- applying selected-calendar range fetches;
- centralizing refresh triggers through `AppAction`.

Adding a future Microsoft Graph provider should mean adding
`Calendar/Providers/Microsoft/...` and implementing the same contracts. Status
bar, notifications, and meeting detection should not change unless the new
provider exposes new structured event fields.

---

## Meetings Architecture

Meeting services should move from a large enum plus scattered switches to a
registry of provider descriptors.

### Provider Identity

Use stable string IDs instead of a closed enum:

```swift
struct MeetingProviderID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}
```

Built-in IDs should be constants:

```swift
extension MeetingProviderID {
    static let googleMeet = MeetingProviderID(rawValue: "google_meet")
    static let zoom = MeetingProviderID(rawValue: "zoom")
    static let teams = MeetingProviderID(rawValue: "teams")
}
```

Persist IDs, not enum cases. Keep a compatibility migration from existing
`MeetingServices` raw values for bookmarks, browser settings, and create-meeting
settings.

Custom user providers must use a reserved namespace such as `custom:<uuid>` so
they cannot collide with built-in provider IDs.

### Provider Descriptor

A provider descriptor declares capabilities:

```swift
struct MeetingProviderDescriptor: Sendable {
    let id: MeetingProviderID
    let displayName: String
    let aliases: [MeetingProviderID]
    let detectionPriority: Int
    let detectionPatterns: [MeetingLinkPattern]
    let icon: MeetingProviderIcon
    let opener: MeetingOpenStrategy
    let createAction: CreateMeetingAction?
    let supportedOpenTargets: [MeetingOpenTarget]
}
```

`aliases` lets variants share behavior and presentation, for example
`zoomgov`, `zoom_native`, and `zoom` can point at the same icon group or opener
where appropriate. `detectionPriority` keeps specific providers ahead of generic
providers. A generic "any link" provider, if kept, must be a last-priority
fallback and must not beat specific meeting services.

Use one opening abstraction. In this document the descriptor uses
`MeetingOpenStrategy`; custom strategies are implemented by
`MeetingProviderOpener`.

A simple provider should be added in one place:

```swift
extension MeetingProviderDescriptor {
    static let luma = MeetingProviderDescriptor(
        id: MeetingProviderID(rawValue: "luma"),
        displayName: "Luma",
        aliases: [],
        detectionPriority: 500,
        detectionPatterns: [
            .regex(#"https://lu\.ma/join/[^\s]*"#)
        ],
        icon: .asset("luma_icon"),
        opener: .browser,
        createAction: nil,
        supportedOpenTargets: [.browser]
    )
}
```

Then register it:

```swift
enum BuiltInMeetingProviders {
    static let all: [MeetingProviderDescriptor] = [
        .googleMeet,
        .zoom,
        .teams,
        .luma
    ]
}
```

No new switch should be needed for detection, icon lookup, browser preferences,
or ordinary opening behavior.

### Detection

`MeetingLinkDetector` should receive a `MeetingProviderRegistry` and iterate
registered providers.

It should keep the existing source priority model:

```text
providerConferenceData
  > eventURL
  > location
  > notes
  > strippedHTMLNotes
  > customRegex
```

Within the same source, longer URLs still win.

Provider-specific normalizers are allowed when they solve a real provider issue:

- Google Meet can append or replace `authuser`;
- Outlook Safe Links can be cleaned before provider matching;
- HTML notes can be stripped before fallback matching.

Do not put provider-specific detection in `MBEvent`.

### Opening

Opening should be strategy-based.

Simple providers use `.browser`. Complex providers provide a custom opener:

```swift
protocol MeetingProviderOpener: Sendable {
    func open(_ link: MeetingLink, context: MeetingOpenContext) async -> MeetingOpenResult
}
```

Custom openers are justified for providers such as:

- Zoom: convert web URLs to `zoommtg://` and fall back to browser;
- Teams: convert to `msteams://` and fall back to browser;
- Slack: build `slack://join-huddle`;
- Riverside: try multiple app schemes before falling back;
- Google Meet: support MeetInOne as a target.

`MeetingOpener` should orchestrate:

1. optional join script;
2. provider opener;
3. fallback browser;
4. user-visible failure notification.

It should not read `Defaults` directly. It receives `MeetingSettings`.

Provider openers must be deterministic and testable. They should depend on
small side-effect abstractions such as a URL opener and notification reporter,
not on `NSWorkspace`, `Defaults`, or global notification helpers directly.

### Creation

Create-meeting options should also be capabilities, not a separate enum that
duplicates provider names.

```swift
struct CreateMeetingAction: Sendable {
    let id: String
    let displayName: String
    let url: URL
    let providerID: MeetingProviderID?
}
```

Providers that can create meetings expose `createAction`. Calendar compose URLs
such as Google Calendar and Outlook can be registered as create actions without
pretending to be meeting-link providers.

### Settings and Migration

Replace per-provider browser keys with a map:

```swift
struct MeetingOpenPreferences: Codable, Sendable {
    var defaultTarget: MeetingOpenTarget
    var providerPreferences: [MeetingProviderID: MeetingOpenPreference]
}
```

Migrate existing keys:

- `meetBrowser` -> provider preference for `google_meet`;
- `zoomBrowser` -> provider preference for `zoom`;
- `teamsBrowser` -> provider preference for `teams`;
- `jitsiBrowser` -> provider preference for `jitsi`;
- `slackBrowser` -> provider preference for `slack`;
- `riversideBrowser` -> provider preference for `riverside`;
- `createMeetingService` -> selected create action ID;
- `bookmarks: [Bookmark]` service enum -> bookmark provider ID.

Keep compatibility decoding for at least one major release so existing users do
not lose bookmarks or browser preferences.

### Custom User Providers

Runtime plugins are out of scope. User-defined providers can be supported later
as data:

```swift
struct CustomMeetingProvider: Codable, Sendable {
    let id: MeetingProviderID
    let displayName: String
    let regexPatterns: [String]
    let iconName: String?
}
```

The registry can merge:

```text
built-in providers + custom providers from settings
```

This gives users and contributors a simple extension path without bundle loading
or plugin security concerns.

---

## Notifications Architecture

Notifications should have five separate responsibilities.

```text
NotificationPlanner
    pure: events + settings + now -> [NotificationPlan]

NotificationScheduler
    side effect: reconcile NotificationPlan with UNUserNotificationCenter

NotificationActionScheduler
    side effect: schedule delayed in-app action tasks when needed

NotificationActionRunner
    side effect: fullscreen, auto-join, on-start script

NotificationCenterDelegate
    adapter: UNUserNotificationCenterDelegate -> AppAction
```

`NotificationScheduler` should not decide whether fullscreen, auto-join, or a
script should fire. It should reconcile notification requests.

`NotificationActionScheduler` exists only if in-app actions still need delayed
tasks independent of system notification requests. It schedules due action plans
and hands execution to `NotificationActionRunner`.

`NotificationActionRunner` should not compute the full notification plan. It
should receive due action plans and execute them through named services.

Processed event records should be behind `NotificationRecordStore`, not direct
`Defaults` reads spread through the scheduler.

---

## Status Bar Architecture

Status bar code should become a renderer plus pure presentation builders.

```text
AppState
  -> StatusBarPresentation
  -> StatusBarController.render(...)

AppState
  -> StatusBarMenuState
  -> StatusBarMenuBuilder.build(...)
```

Rules:

- `StatusBarController` owns `NSStatusItem` and AppKit rendering only;
- it should not store `events`;
- it should not ask `EventManager` for refreshes directly;
- it should not read `Defaults`;
- it should not compute `nextEvent`;
- `StatusBarMenuBuilder` builds menu items from `StatusBarMenuState`;
- menu item actions should call a small action handler that sends `AppAction`s.

The existing attributed title logic can stay AppKit-specific in
`StatusBarTitleRenderer`. The decision about what title, icon, layout, tooltip,
and fallback mode to show belongs in `StatusBarPresentation`.

Keep `NSStatusItem`. The current feature set depends on AppKit-level control.

---

## Windows, URL Handling, and Lifecycle

`AppDelegate` should become the composition root.

Target responsibilities:

```text
AppDelegate
  - create AppEnvironment
  - create AppModel
  - create coordinators
  - connect OS delegates
  - start the app

WindowCoordinator
  - onboarding
  - preferences
  - changelog
  - fullscreen notification windows

URLHandler
  - meetingbar://preferences
  - OAuth callback forwarding

LifecycleObserver
  - lock/unlock
  - wake
  - timezone changed
  - calendar day changed

NotificationCenterDelegate
  - willPresent
  - didReceive response
```

These adapters should send `AppAction`s or call explicit environment services.
They should not own business rules.

---

## Testing Strategy

Before each risky migration, add characterization tests for the behavior being
moved.

Keep the hostless SwiftPM logic package. It is a test tool, not a product
architecture boundary. As feature folders replace `Core/Policies`, update
`Package.swift` to include the pure files from those folders so `make
test-logic` remains fast.

Preferred test placement:

- pure decisions: hostless logic tests;
- calendar provider mappers/parsers: unit tests with fixture payloads;
- meeting provider registry and detection: hostless tests;
- notification planning: hostless tests;
- notification scheduling diff logic: host tests or sink-backed tests;
- status bar AppKit rendering: host tests;
- `AppModel` action handling: unit tests with fake environment services.

Required characterization areas:

- next-event selection and filtering;
- meeting link candidate ranking;
- provider-specific meeting open fallback behavior;
- notification plan identity stability;
- failed refresh preserving last known events;
- status bar presentation for long titles, hidden titles, no calendars, no
  events, ongoing events, and threshold mode;
- migration of existing meeting provider settings and bookmarks.

The architecture is successful only if tests become easier to write, not harder.

---

## Migration Plan

The canonical execution plan is
[`ARCHITECTURE_MIGRATION_PLAN.md`](ARCHITECTURE_MIGRATION_PLAN.md).

This document intentionally avoids duplicating phase details. The short rule is:
add characterization tests first, extract boundaries second, and move files only
after ownership is clear. Keep the roadmap aligned with these decisions before
implementation starts.

---

## Definition of Done

The migration is done when these statements are true:

- `AppDelegate` is a composition root, not a god object.
- `StatusBarController` does not store events and does not read `Defaults`.
- `NotificationScheduler` reconciles system notifications but does not own
  in-app action decisions.
- `EventStore` has no OAuth-only requirements.
- Google and EventKit code live in separate provider folders.
- Adding a simple meeting provider requires:
  - one provider descriptor;
  - one detection pattern;
  - optional icon asset;
  - tests.
- Existing user bookmarks and meeting browser preferences migrate safely.
- `Defaults` usage in feature logic is replaced by `AppSettings` snapshots.
- Preferences and Onboarding use shared settings/provider components and no
  longer reach into `AppDelegate`, `EventManager`, or raw `Defaults`.
- Wake/unlock/timezone/day-change behavior is visible as app actions.
- The contributor-facing architecture doc matches the code.

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Xcode project churn from file moves | Move files in focused PRs and avoid unrelated edits. |
| Behavior regressions in meeting opening | Add provider opener characterization tests before replacing switches. |
| Lost user settings during provider ID migration | Keep compatibility decoding and write migration tests. |
| AppModel becoming a new god object | Keep side effects in `AppEnvironment` and feature services. Keep derived logic in feature builders. |
| Too many protocols | Add protocols only at side-effect/provider boundaries. Prefer structs/enums for pure values. |
| Reviewer fatigue | Ship phases as small PRs with behavior-preserving commits first. |

---

## Explicit Rejections

Rejected for this migration:

- **SwiftPM core package.** Valuable later, too much project churn now.
- **TCA.** Useful architecture, but too much framework knowledge for a small
  open-source menu bar app.
- **MenuBarExtra rewrite.** It would remove AppKit control MeetingBar currently
  relies on.
- **Runtime plugin loading for meeting providers.** Descriptor-based custom
  providers cover the practical need with less security and maintenance risk.
- **Folder per simple meeting service.** Use provider descriptors. Create a
  folder only when a provider has real custom behavior.
- **Full visual rebrand.** Preferences and Onboarding need an architecture-led
  redesign. The rest of the app should not be redesigned as part of this
  migration.

---

## Open Decisions

These should be decided before implementation, but they do not block agreeing on
the architecture:

- whether 5.0 bumps the minimum deployment target to macOS 13;
- whether user-defined custom meeting providers are included in the first
  registry migration or deferred;
- whether the final Preferences shell remains a macOS 12-compatible `TabView`
  or moves to a sidebar after the platform decision;
- exact naming for `CalendarRepository` versus `EventRefreshService`.

The architecture should not depend on the answers to these except where noted.
