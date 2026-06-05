# MeetingBar Architecture

This document is the contributor-facing map of the codebase. It complements [`ROADMAP.md`](../ROADMAP.md) (planning) and [`CLAUDE.md`](../CLAUDE.md) (AI agent instructions). Read this first if it is your first time touching MeetingBar.

If anything below disagrees with the actual code, the code wins — and the doc needs a fix.


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
                     │ events + calendars + active provider
                     ▼
            ┌────────────────────┐
            │      AppModel      │  @MainActor ObservableObject
            │  AppState (value)  │  driven by AppAction via AppEnvironment
            │  • events          │
            │  • calendars       │
            │  • active provider │
            └────────┬───────────┘
                     │
        ┌────────────▼──────────────┬──────────────────┐
        │ StatusBar                 │ Notification     │
        │ ItemController            │ Scheduler        │
        │ + MenuBuilder             │ (mb-plan-…)      │
        │ (via StatusBarMenuState)  │ + delayed Tasks  │
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
MeetingBar/                         (~74 .swift files)
├── App/                            — process lifecycle, OS integration
│   ├── AppDelegate.swift           — @main; composition root; wires LifecycleObserver, URLHandler, AppModel
│   ├── AppMessageCenter.swift      — one adapter for user notifications and fallback alerts
│   ├── AppModel.swift              — @MainActor ObservableObject + AppState + AppAction + AppEnvironment
│   ├── AppIntent.swift             — Shortcuts integration
│   ├── LifecycleObserver.swift     — screen-lock / wake / timezone / day-change notifications
│   ├── Notifications.swift         — shared notification identifiers and data types
│   ├── PatronageService.swift      — StoreKit 2 purchases, restore, entitlements, transaction updates
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
│   ├── MBEvent.swift               — cross-provider event + filtered() / nextEvent() helpers
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
│   ├── MeetingProvider.swift       — struct + static all (single source of provider metadata) [SPM]
│   ├── MeetingServices.swift       — enum extensions: localization, icons, opening, create-meeting URLs
│   ├── MeetingLinkDetector.swift   — MeetingServices enum + MeetingLink + helpers + Candidate + OpeningPolicy [SPM]
│   ├── MeetingOpener.swift         — runs join script + opens URL + per-provider OpenStrategy structs
│   └── MeetingOpenPreferencesMigration.swift — migrates old per-provider browser prefs
│
├── Notifications/                  — UN notification scheduling + actions
│   ├── EventActionPolicy.swift     — should fullscreen / auto-join / script fire? [SPM]
│   ├── NotificationPlanner.swift   — desired UN requests for an event [SPM]
│   ├── NotificationScheduler.swift — reconciles plans with UNUserNotificationCenter; owns content + action scheduling
│   ├── NotificationActionRunner.swift    — executes fullscreen / auto-join / script; owns processed-event records
│   ├── NotificationCenterDelegate.swift  — UNUserNotificationCenterDelegate
│   └── NotificationSetup.swift           — requests UN authorization
│
├── Settings/
│   └── AppSettings.swift           — value-type settings groups + AppSettings.current factory (single Defaults boundary)
│
├── Preferences/                    — SwiftUI Settings window tabs (General/Appearance/…/Status)
├── Onboarding/                     — multi-screen first-launch flow
├── UI/
│   ├── StatusBar/                  — menu bar item, menu construction, presentation
│   │   ├── StatusBarItemController.swift   — owns NSStatusItem, render only
│   │   ├── MenuBuilder.swift               — builds NSMenu from StatusBarMenuState (zero Defaults reads)
│   │   ├── StatusBarMenuState.swift        — value type + .make(from:) factory
│   │   ├── StatusBarPresentation.swift     — Presentation + Title + Icon policies and Presenter [SPM]
│   │   └── StatusBarPresentation+MeetingBar.swift — Defaults adapters for all three policies
│   └── Views/                      — remaining SwiftUI views (DayTimelineView, FullscreenNotification, Changelog/)
│
├── Utilities/
│   ├── Constants.swift
│   ├── Helpers.swift
│   ├── I18N.swift
│   ├── Keychain.swift
│   ├── MeetingBarLogger.swift      — os.Logger categories and privacy-aware structured logging
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

## Migration rule for new architecture work

The migration target is deliberately simple:

```text
UI sends actions.
AppModel coordinates.
Feature components own workflows.
Policies decide.
macOS integrations execute side effects.
```

Use MeetingBar names for new boundaries (`EventManager`, `MeetingOpener`, `NotificationScheduler`, `AppSettings`, `WindowCoordinator`) rather than generic architecture labels. A new type is useful only if it gives a workflow one obvious owner or makes a decision testable.

Current PR gate for architecture changes:

1. Add or update tests around the owner that receives moved behavior.
2. Keep old production paths only when the next PR removes them explicitly.
3. Run `make lint`, `make validate-strings`, `make test-logic-quiet`, and the app-hosted test/build path for app-target changes.
4. If the PR touches project files, entitlements, URL schemes, dependencies, scripts, workflows, or base localization, call that out in the PR description.

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
.throttle(for: .milliseconds(200), latest: false)  // pass first trigger, collapse the burst
.flatMap(maxPublishers: 1) { _ in
    fetchEverything()                              // one in flight at a time
}
.sink { [weak self] result in
    self?.publish(result)                          // [MBCalendar], [MBEvent], ProviderHealth
}
```

Three things to internalize:

1. **`throttle(200ms)` collapses bursts.** When the user flips three checkboxes in Preferences within 50 ms, we do one fetch, not three. `latest: false` lets the first trigger through immediately, which keeps manual refresh responsive.
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
        │       .eventStart, .eventEnd
        ▼
NotificationScheduler.reconcile(events:settings:now:)   ← side-effecting service
   • build mb-plan-<eventID>-<kind> identifiers
   • diff against UNUserNotificationCenter.pendingNotificationRequests
   • remove obsolete, add missing, replace if content changed
   • inject `now` for testability
```

**Why "mb-plan-" identifiers matter.** They are stable per (event, kind). Reconcile is idempotent: calling it twice in a row is a no-op. Calling it after a settings change re-arms only what changed. This replaced an older "single-id" model that suppressed back-to-back events.

**`NotificationActionRunner`** handles in-app actions (fullscreen, auto-join, on-start script) triggered at event start. The scheduler owns delayed `Task`s for these actions and dispatches to the runner; the runner persists processed-event records (a fileprivate `NotificationRecordStore`) to avoid re-firing on re-reconcile.

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

`AppModelTestHarness` wires `AppModel` to in-memory publishers and recording closures. Use it for AppAction scenarios before moving behavior out of AppDelegate, StatusBar, AppIntent, Preferences, or notification delegates.

Current logic coverage baseline, recorded when strict concurrency was made explicit: hostless source-region coverage is about 95.9%, with line coverage about 99.1%. Keep coverage visible during the migration; do not chase total percentage by testing trivial wrappers.

---

## Strict concurrency and CI expectations

Swift 6 strict concurrency is explicit in both Xcode settings and the SwiftPM logic package. Framework interop exceptions (`@unchecked Sendable`, `nonisolated(unsafe)`) are allowed only where Apple or third-party types require them, and touched exceptions need a short owner comment.

CI is split by responsibility:

- `main.yml` validates localization keys, runs SwiftPM logic tests, and runs the Xcode app-hosted build/test path with coverage.
- `swiftlint.yml` runs SwiftLint and is triggered by Swift, config, project, script, workflow, and base-localization changes.

The local unsigned Debug build may print the entitlements/code-signing warning when `CODE_SIGNING_REQUIRED=NO`; that is not a Swift warning and is expected for local verification.

---

## Async task ownership

Long-running or delayed work must have one stored owner and an explicit cancellation path. Short UI callback hops may remain untracked only when they do not loop, sleep for workflow timing, or retain feature state.

| Work | Owner | Cancellation path |
|---|---|---|
| App launch setup and notification authorization | `AppDelegate` | `applicationWillTerminate` |
| Minute-boundary status refresh loop | `AppDelegate` | `applicationWillTerminate` / quit |
| Provider change, snooze, onboarding, notification reconcile, refresh actions | `AppModel` | `.willTerminate`; replacement cancels superseded work |
| Calendar refresh cycle and store-change refresh | `EventManager` | `stop()` |
| Active provider operations | `CalendarRepository` / `EventStore` | provider switch and `stop()` call `cancelPendingOperations()` |
| Google OAuth sign-in, token refresh, external authorization session | `GCEventStore` | sign-out, provider switch, app termination |
| Delayed fullscreen, auto-join, and event-start script actions | `NotificationScheduler` | reconcile removes stale plans; `stop()` cancels all |
| StoreKit transaction update listener | `PatronageService` | `stop()` |
| Lifecycle notification registrations | `LifecycleObserver` | `stop()` |

Deliberate bounded exceptions:

- EventKit uses `Task.detached` for blocking EventKit enumeration/fetch calls. Every detached task is immediately awaited, so ownership remains with the calling refresh cycle.
- `AppMessageCenter.post`, lifecycle callback hops, diagnostics clipboard copy, and SwiftUI button tasks are short-lived adapters. They must not grow loops or delayed workflow scheduling; promote them to a stored owner if that changes.

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

`EventStore` contains provider-neutral fetch and cancellation operations. `AuthenticatedEventStore` extends it with explicit authorization/sign-out. Google uses that boundary for OAuth; EventKit uses it for calendar permission.

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
2. **Add the setting.** New key in `Extensions/DefaultsKeys.swift`. Read it once in `NotificationPlanningSettings.currentForScheduler` (the adapter).
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
make build-quiet     # Debug build with filtered output
make build-release   # Release build
make test            # Full suite with coverage (host + logic)
make test-quiet      # Full suite with filtered output
make test-logic      # Hostless logic tests only — fast
make test-logic-quiet # Hostless logic tests with filtered output
make lint            # SwiftLint
make validate-strings # Verify every .loco() key exists in en.lproj/Localizable.strings
make open            # Open in Xcode
```

Local dev team override: create `XCConfig/DevTeamOverride.xcconfig` (git-ignored) with `DEVELOPMENT_TEAM = <id>`.

SwiftLint disabled rules: `file_length`, `function_body_length`, `type_body_length`, `type_name`, `force_cast`, `force_try`, `force_unwrapping`. Line-length warning at 200, error at 250. Do not introduce new force unwraps in touched code unless the failure is impossible and a comment explains why.

---

## Release-sensitive files

Treat these as architecture-owned, release-sensitive files. Changes should be named in PR notes and covered by CI where possible:

- `MeetingBar.xcodeproj/project.pbxproj`
- `MeetingBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `Package.swift`
- `XCConfig/**`
- `MeetingBar/MeetingBar.entitlements`
- `MeetingBar/Info.plist`
- `.github/workflows/**`
- `Scripts/**`
- `MeetingBar/Resources /Localization /en.lproj/Localizable.strings`

For dependency changes, explain why the package remains or how it is being removed. For App Store/direct-build differences, verify app-source behavior, signing assumptions, URL schemes, sandbox capabilities, and localization validation before release.

The concrete dependency policy and release procedure live in [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md).

---

## Pointers

- Planning, release scope, open issues triage: [`ROADMAP.md`](../ROADMAP.md)
- Dependencies, signing, capabilities, StoreKit, and release verification: [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
- AI agent operating instructions: [`CLAUDE.md`](../CLAUDE.md), [`AGENTS.md`](../AGENTS.md)
- Localization: `MeetingBar/Resources /Localization /` (note the spaces in the path — historical)
- Meeting service URL patterns: [`MeetingBar/Meetings/MeetingServices.swift`](../MeetingBar/Meetings/MeetingServices.swift)
- All persistent settings keys: [`MeetingBar/Extensions/DefaultsKeys.swift`](../MeetingBar/Extensions/DefaultsKeys.swift)
