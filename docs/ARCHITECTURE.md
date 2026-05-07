# MeetingBar Architecture

This document is the contributor-facing map of the codebase. It complements [`ROADMAP.md`](../ROADMAP.md) (planning) and [`CLAUDE.md`](../CLAUDE.md) (AI agent instructions). Read this first if it is your first time touching MeetingBar.

If anything below disagrees with the actual code, the code wins — and the doc needs a fix.

For the proposed next architecture, see [`ARCHITECTURE_UPDATE.md`](ARCHITECTURE_UPDATE.md). For the Preferences/Onboarding UI migration, see [`PREFERENCES_ONBOARDING_REDESIGN_PLAN.md`](PREFERENCES_ONBOARDING_REDESIGN_PLAN.md). This file describes the current code; the update documents describe the migration target.

---

## What MeetingBar is, in one paragraph

MeetingBar is a macOS menu-bar app that reads calendars (Apple Calendar via EventKit, Google Calendar via OAuth2), shows the next event in the system status bar, opens the right meeting URL when you click "Join", and fires notifications around event start/end. It is `NSApplicationDelegate`-based (AppKit) with SwiftUI used for Preferences/Onboarding/Fullscreen views. macOS 12+ minimum, Swift 6.

The product principle is reliability first: **show the correct meeting, stay fresh, stay visible, open the right link**. New settings are a last resort — improve the default behavior instead.

---

## Top-level data flow

```
                ┌──────────────────────────────────────────────┐
                │                Calendar providers            │
                │   EKEventStore (Apple)   GCEventStore (GCal) │
                └───────────────▲──────────────────────────────┘
                                │ fetchAllCalendars / fetchEventsForDateRange
                                │
            ┌───────────────────┴────────────────────┐
            │             EventManager               │  @MainActor ObservableObject
            │  Combine pipeline merges 3 triggers:   │
            │   1. Defaults changes                  │
            │   2. 3-minute timer                    │
            │   3. manual refresh (refreshSubject)   │
            │  → throttle(200ms)                     │
            │  → flatMap(maxPublishers: 1) fetch     │
            │  → publish [MBCalendar], [MBEvent],    │
            │            ProviderHealth              │
            └────────┬───────────────────────────────┘
                     │ events + calendars + health
                     ▼
            ┌────────────────────┐
            │      AppModel      │  @MainActor ObservableObject
            │  AppState (value)  │  driven by AppAction via AppEnvironment
            │  • events          │
            │  • calendars       │
            │  • provider health │
            └────────┬───────────┘
                     │
        ┌────────────▼──────────────┬──────────────────┐
        │ StatusBar                 │ Notification     │
        │ ItemController            │ Scheduler        │
        │ + MenuBuilder             │ (mb-plan-…)      │
        │ (via StatusBarMenuState)  │ + ActionScheduler│
        │                           │ + ActionRunner   │
        └───────┬───────────────────┴──────────────────┘
                │
                ▼
         macOS menu bar
```

**Read this top-down** when debugging "the menu bar shows the wrong thing": the bug is at one of these layers, not spread across them.

---

## Directory map

```
MeetingBar/
├── App/                            — process lifecycle, OS integration
│   ├── AppDelegate.swift           — @main; wires LifecycleObserver + URLHandler + AppModel
│   ├── AppAction.swift             — sealed enum of all user/system intents
│   ├── AppEnvironment.swift        — side-effect commands keyed by AppAction
│   ├── AppModel.swift              — @MainActor ObservableObject owning AppState
│   ├── AppState.swift              — value-type snapshot of app runtime state
│   ├── AppIntent.swift             — Shortcuts integration
│   ├── AppStore.swift              — IAP via SwiftyStoreKit
│   ├── LifecycleObserver.swift     — screen-lock / wake / timezone / day-change notifications
│   ├── Notifications.swift         — UN auth + snooze flow + low-level send
│   └── URLHandler.swift            — apple-event URL dispatch (oauth, preferences)
│
├── Calendar/                       — calendar data: models, events, filtering, selection, providers
│   ├── EventStore.swift            — EventStore protocol (provider abstraction)
│   ├── CalendarRepository.swift    — owns the active store, exposes fetch + switch
│   ├── EventManager.swift          — refresh pipeline (Combine, @MainActor)
│   ├── EventFiltering.swift        — apply user filters (all-day, declined, etc.) [SPM]
│   ├── EventFiltering+MeetingBar.swift
│   ├── EventSelection.swift        — pick the "next" event from a list [SPM]
│   ├── EventSelection+MeetingBar.swift
│   ├── MBEvent.swift               — cross-provider event
│   ├── MBEvent+Helpers.swift
│   ├── MBCalendar.swift            — cross-provider calendar
│   ├── ProviderHealth.swift        — auth/stale/error/ok
│   └── Providers/
│       ├── EventKit/
│       │   └── EventKitEventStore.swift    — Apple Calendar via EventKit
│       └── Google/
│           ├── GoogleCalendarEventStore.swift — Google Calendar via AppAuth + REST
│           └── GoogleCalendarPolicy.swift     — auth/error classification [SPM]
│
├── Meetings/                       — meeting URL detection, opening, services catalog
│   ├── MeetingLinkCandidate.swift  — scored URL + source priority [SPM]
│   ├── MeetingLinkDetection.swift  — extraction helpers [SPM]
│   ├── MeetingLinkDetector.swift   — orchestrates URL extraction [SPM]
│   ├── MeetingOpener.swift         — runs join script + opens meeting URL
│   ├── MeetingOpeningPolicy.swift  — open-in-browser vs open-in-app logic [SPM]
│   ├── MeetingServices.swift       — regex catalog of 50+ meeting URL patterns
│   ├── Domain/
│   │   ├── MeetingProviderDescriptor.swift — value type for a meeting provider [SPM]
│   │   └── MeetingProviderRegistry.swift   — catalog of all descriptors [SPM]
│   ├── Opening/
│   │   ├── MeetingOpenStrategy.swift       — open-in-app vs browser logic
│   │   ├── MeetingOpenerRegistry.swift     — maps provider ID to strategy
│   │   └── MeetingOpenPreferencesMigration.swift — migrates old per-provider browser prefs
│   └── Creation/
│       └── CreateMeetingRegistry.swift     — maps CreateMeetingService to URL factory
│
├── Notifications/                  — UN notification scheduling + actions
│   ├── EventActionPolicy.swift     — should fullscreen / auto-join / script fire? [SPM]
│   ├── NotificationPlanner.swift   — desired UN requests for an event [SPM]
│   ├── NotificationScheduler.swift — reconciles plans with UNUserNotificationCenter
│   ├── NotificationActionScheduler.swift — decides when to run in-app actions
│   ├── NotificationActionRunner.swift    — executes fullscreen / auto-join / script
│   ├── NotificationCenterDelegate.swift  — UNUserNotificationCenterDelegate
│   ├── NotificationContentFactory.swift  — builds UNMutableNotificationContent
│   ├── NotificationRecordStore.swift     — persists processed event IDs
│   └── NotificationSetup.swift           — requests UN authorization
│
├── UI/
│   ├── StatusBar/                  — menu bar item, menu construction, policies
│   │   ├── StatusBarItemController.swift
│   │   ├── MenuBuilder.swift
│   │   ├── StatusBarMenuState.swift        — value type carrying all menu-building inputs
│   │   ├── StatusBarMenuStateFactory.swift — builds StatusBarMenuState from AppModel
│   │   ├── StatusBarPresentation.swift    — value types + StatusBarPresentationPolicy + StatusBarPresenter [SPM]
│   │   ├── StatusBarPresentation+MeetingBar.swift
│   │   ├── StatusBarTitlePolicy.swift     — title text formatting [SPM]
│   │   ├── StatusBarTitlePolicy+MeetingBar.swift
│   │   ├── StatusBarIconPolicy.swift      — icon selection [SPM]
│   │   └── StatusBarIconPolicy+MeetingBar.swift
│   ├── Views/Preferences/          — SwiftUI tabs (General/Appearance/…/Status)
│   ├── Views/Onboarding/           — multi-screen onboarding
│   ├── Views/FullscreenNotification.swift
│   └── Views/Changelog/
│
├── Utilities/
│   ├── Constants.swift
│   ├── Helpers.swift
│   ├── I18N.swift
│   ├── Keychain.swift
│   ├── Scripts.swift               — AppleScript runners
│   └── Diagnostics/                — issue-report formatter [SPM]
│
├── Extensions/
│   ├── DefaultsKeys.swift          — every persistent setting key
│   └── KeyboardShortcutsNames.swift
│
└── Resources /Localization /       — Localizable.strings, 20+ locales (Weblate)
```

Tests live in `MeetingBarTests/` (host-app tests, AppKit-aware) and `MeetingBarLogicTests/` (hostless, Package.swift, fast).

---

## The "policy + adapter" pattern

You will see pairs of files like:

- `EventSelection.swift`
- `EventSelection+MeetingBar.swift`

This is intentional. The pattern is:

| File | Imports | Knows about |
|---|---|---|
| `Foo.swift` | `Foundation` only | Plain data, no `Defaults`, no AppKit, no `MBEvent` directly |
| `Foo+MeetingBar.swift` | `Defaults`, `MBEvent`, AppKit if needed | Bridges the policy to the real app |

**Why.** The first file lives in the `MeetingBarLogic` SwiftPM target. It runs in `make test-logic` without launching the host app — fast, no calendar permission prompts, no `XCUIApplication`. The adapter file pulls in app-specific types (Defaults snapshots, `MBEvent → StatusBarEventPresentationInput`, etc.) and is built only as part of the main app target.

**When you write a new policy:**

1. Put the pure decision in `Foo.swift`. Take `struct FooSettings` and primitive inputs (Date, Int, String, your own enums). Return a value.
2. Put `extension FooSettings { static var current: FooSettings { … reads Defaults … } }` and any `init(MBEvent)` mappers in `Foo+MeetingBar.swift`.
3. Add `Foo.swift` to `Package.swift` sources (and to the Xcode target — it ships in both).
4. Write tests against `Foo.swift` in `MeetingBarLogicTests/`.

**When NOT to use this pattern:** if your code genuinely needs `NSImage`, `NSStatusItem`, `UNUserNotificationCenter`, or other AppKit/UN types, it is a **service**. Put it alongside the feature it serves (e.g. `Notifications/NotificationScheduler.swift`) and accept that its tests will be host-app tests.

---

## How EventManager refreshes (the part that confuses everyone)

`EventManager` is a `@MainActor ObservableObject` and the heart of the data flow. Its refresh pipeline merges three Combine publishers:

```swift
// Conceptual — see Calendar/EventManager.swift for the real thing.
Publishers.Merge3(
    defaultsChanges,           // user toggled a setting
    Timer.publish(every: 180), // every 3 minutes
    refreshSubject             // somebody called .refreshSources()
)
.throttle(for: .milliseconds(200), latest: true)   // collapse bursts
.flatMap(maxPublishers: 1) { _ in
    fetchEverything()                              // one in flight at a time
}
.sink { [weak self] result in
    self?.publish(result)                          // [MBCalendar], [MBEvent], ProviderHealth
}
```

Three things to internalize:

1. **`throttle(200ms)` collapses bursts.** When the user flips three checkboxes in Preferences within 50 ms, we do one fetch, not three. `latest: true` means we keep the *last* value, not the first.
2. **`flatMap(maxPublishers: 1)` serializes fetches.** While a fetch is in flight, new triggers wait. There is no parallel refresh and no "most recent wins" race.
3. **Failed refresh preserves last known events and calendars.** This is enforced in the publish step: we never replace a non-empty list with an empty one because of a network failure. `ProviderHealth` is the place where errors surface, not the event list.

If you are tempted to "just trigger a refresh from over here" — call `eventManager.refreshSources()` (or send to `refreshSubject`). Do not duplicate the fetch logic.

---

## Notifications: the reconciler model

`NotificationScheduler` (`Notifications/NotificationScheduler.swift`) does **not** directly schedule one notification per user action. It owns a *desired plan* and reconciles it against `UNUserNotificationCenter`'s actual pending requests.

```
events + Defaults snapshot
        │
        ▼
NotificationPlanner.plan(events:settings:now:)   ← pure [SPM]
        │  → [NotificationPlan] with kinds:
        │       .eventStart, .endOfEvent
        ▼
NotificationScheduler.reconcile(events:settings:now:)   ← side-effecting service
   • build mb-plan-<eventID>-<kind> identifiers
   • diff against UNUserNotificationCenter.pendingNotificationRequests
   • remove obsolete, add missing, replace if content changed
   • inject `now` for testability
```

**Why "mb-plan-" identifiers matter.** They are stable per (event, kind). Reconcile is idempotent: calling it twice in a row is a no-op. Calling it after a settings change re-arms only what changed. This replaced an older "single-id" model that suppressed back-to-back events.

**`NotificationActionScheduler` + `NotificationActionRunner`** handle in-app actions (fullscreen, auto-join, on-start script) that are triggered at event start. They read the `NotificationRecordStore` to avoid re-firing on re-reconcile.

---

## Status bar rendering

`StatusBarItemController` manages the `NSStatusItem` and is the *only* place that touches AppKit for the menu bar item. The rendering decision is split:

```
StatusBarPresentationPolicy.mode(...)      → idle / noUpcoming / nextEvent / afterThreshold
StatusBarTitlePolicy.text(...)             → final title + time strings
StatusBarIconPolicy.icon(...)              → which NSImage to use
StatusBarPresenter.presentation(...)       → bundles all of the above into StatusBarPresentation
                                             (compact fallback, layout, titleStyle, tooltip)
```

`StatusBarItemController.updateTitle()` calls `StatusBarPresenter.presentation(...)` and then *only renders*. It does not decide anything. If you want to change *what* is shown, edit a policy. If you want to change *how* it is drawn (font, attributed string, click target), edit the controller.

**Visibility is a reliability concern, not customization.** A long event title must never push the icon off the menu bar. The `compactFallback` flag in `StatusBarPresentation` triggers an icon-only fallback. Do not add a setting for "show icon when title is long" — the default must already be correct.

---

## Meeting link detection

`MeetingLinkDetector` builds a list of `MeetingLinkCandidate`s with explicit source priority:

```
providerConferenceData  (Google conferenceData.entryPoints)
      > eventURL        (EKEvent.url, GCal htmlLink-derived)
      > location
      > notes
      > strippedHTMLNotes
      > customRegex     (user-defined fallback)
```

Within one source, longer URLs win when one is a prefix of another (Zoom truncation case). The chosen candidate becomes `MBEvent.meetingLinkCandidate`; the rest stay as `MBEvent.alternateMeetingLinkCandidates` so the menu can offer "join with another link".

**Do not put link-choosing logic in `MBEvent.init`.** Models are data; the detector is a policy.

---

## Hostless tests vs host tests

| Suite | Location | Run with | Speed | Use for |
|---|---|---|---|---|
| Hostless | `MeetingBarLogicTests/` | `make test-logic` | Fast (~1s) | Policies, formatters, link detection, plan generation |
| Host | `MeetingBarTests/` | `make test` | Slower, launches app | `MenuBuilder`, status item rendering, anything that needs `NSImage`/AppKit |

**Default to hostless.** A test that needs to launch the app is a signal that you are testing a service, not a policy. That is fine — but write it consciously. Hostless tests run on every PR and contribute the bulk of the 200+ test count.

`BaseTestCase` (host suite) snapshots and restores `UserDefaults` around each test. `FakeEventStore` lets you inject controlled event lists into `EventManager`.

---

## Settings (`Defaults`) discipline

All persistent settings keys live in `Extensions/DefaultsKeys.swift` and are read via the `Defaults` library.

The rule: **read `Defaults` at boundaries, not deep inside policies.** Each policy that needs settings exposes a `FooSettings` struct and a `static var current` factory in its adapter file:

```swift
extension StatusBarPresentationSettings {
    static var current: StatusBarPresentationSettings {
        StatusBarPresentationSettings(
            hasSelectedCalendars: !Defaults[.selectedCalendarIDs].isEmpty,
            showEventMaxTimeUntilEventEnabled: Defaults[.showEventMaxTimeUntilEventEnabled],
            showEventMaxTimeUntilEventThreshold: Defaults[.showEventMaxTimeUntilEventThreshold]
        )
    }
}
```

The policy itself takes the snapshot and never imports `Defaults`. This is what keeps the policy hostless-testable.

**When to add a new setting.** Per the roadmap product guardrails: only when the behavior is genuinely subjective, common, easy to explain, and low-risk. First try improving the default. A "fix" that adds two new toggles is usually the wrong fix.

---

## Provider abstraction

`EventStore` (`Calendar/EventStore.swift`) is the seam between the app and a calendar provider. Two implementations ship today:

- **`EKEventStore`** — wraps EventKit. Always available; permission prompt the first time. No OAuth.
- **`GCEventStore`** — wraps Google Calendar API via AppAuth-iOS. OAuth2 flow with refresh tokens persisted in Keychain. Per-calendar 403 handling so one inaccessible calendar does not disconnect the account.

The protocol currently has OAuth-only members (`signIn(forcePrompt:)`, `signOut()`) that EventKit stubs out. The 5.0 plan reshapes the protocol so OAuth is its own sub-protocol — see ROADMAP Phase "5.0".

**Adding a third provider** (e.g. Microsoft Graph in 5.x): implement `EventStore`, map provider events into `MBEvent`, expose calendars as `MBCalendar`. Do not push provider-specific types past the store boundary — the rest of the app must remain provider-agnostic.

---

## High-risk files

Touching these requires extra care, tests around behavior, and a focused PR. Listed in `ROADMAP.md` and reproduced here:

- `App/AppDelegate.swift`
- `Calendar/EventManager.swift`
- `UI/StatusBar/StatusBarItemController.swift`
- `UI/StatusBar/MenuBuilder.swift`
- `Calendar/MBEvent.swift`, `MBEvent+Helpers.swift`
- `Calendar/Providers/Google/GoogleCalendarEventStore.swift`
- `Calendar/Providers/EventKit/EventKitEventStore.swift`
- `Notifications/NotificationScheduler.swift`
- `Meetings/MeetingLinkDetector.swift`
- `Meetings/MeetingServices.swift`
- `App/Notifications.swift`

Before changing one of these, check `ROADMAP.md` to confirm your change aligns with the current phase.

---

## How to add a new feature: a worked example

You want to add "do not notify for events shorter than 5 minutes".

1. **Decide where the rule lives.** It is a per-event filter for notifications → it belongs in `NotificationPlanner`, not in the scheduler service.
2. **Add the setting.** New key in `Extensions/DefaultsKeys.swift`. Read it once in `NotificationPlanSettings.current` (the adapter).
3. **Update the policy.** Inside `NotificationPlanner.plan(for:settings:now:)`, return `[]` when `event.duration < settings.minDurationForNotifications`.
4. **Test it hostless.** Add a case in `MeetingBarLogicTests/NotificationPlannerTests.swift`: short event → empty plan; long event → plan unchanged.
5. **Update the UI.** Add a toggle in the relevant Preferences tab. Localize the label and add the key to `en.lproj/Localizable.strings`. Run `make validate-strings`.
6. **Reconcile triggers.** Make sure `StatusBarItemController.setupDefaultsObservers()` (or wherever the watcher list lives) listens to your new key so flipping it triggers a notification reconcile.
7. **Open a small PR.** Body: rule, why a default tweak alone is not enough, screenshots if UI, test names.

The whole change should be ~50 lines and no changes to `EventManager` or `AppDelegate`.

---

## Build, lint, test commands

```bash
make build           # Debug build
make build-release   # Release build
make test            # Full suite with coverage (host + logic)
make test-logic      # Hostless logic tests only — fast
make lint            # SwiftLint
make validate-strings # Verify every .loco() key exists in en.lproj/Localizable.strings
make open            # Open in Xcode
```

Local dev team override: create `XCConfig/DevTeamOverride.xcconfig` (git-ignored) with `DEVELOPMENT_TEAM = <id>`.

SwiftLint disabled rules: `file_length`, `function_body_length`, `type_body_length`, `type_name`, `force_cast`, `force_try`, `force_unwrapping`. Line-length warning at 200, error at 250. Do not introduce new force unwraps in touched code unless the failure is impossible and a comment explains why.

---

## Pointers

- Planning, release scope, open issues triage: [`ROADMAP.md`](../ROADMAP.md)
- AI agent operating instructions: [`CLAUDE.md`](../CLAUDE.md), [`AGENTS.md`](../AGENTS.md)
- Localization: `MeetingBar/Resources /Localization /` (note the spaces in the path — historical)
- Meeting service URL patterns: [`MeetingBar/Services/MeetingServices.swift`](../MeetingBar/Services/MeetingServices.swift)
- All persistent settings keys: [`MeetingBar/Extensions/DefaultsKeys.swift`](../MeetingBar/Extensions/DefaultsKeys.swift)
