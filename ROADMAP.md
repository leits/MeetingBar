# MeetingBar Roadmap

Last updated: 2026-05-02

This file is the single source of truth for MeetingBar planning. Use it for AI agents and human contributors alike. If older planning notes (e.g. a `dev_plan.md`) disagree, this file wins.

---

## Product principle

MeetingBar must be a trustworthy meeting entrypoint.

It should:

- show the correct current or next meeting;
- stay fresh after sleep, wake, unlock, provider refresh, and settings changes;
- remain visible in the macOS menu bar;
- open the correct meeting link;
- clearly explain stale, auth, calendar permission, and provider failures.

Reliability and correctness come before new features, UI polish, and extra settings.

---

## Product guardrails

MeetingBar should stay simple, reliable, and contributor-friendly.

When user feedback asks for a new behavior, prefer this order:

1. Improve the default behavior.
2. Add clearer diagnostics or explanation.
3. Reuse or clarify an existing setting.
4. Add a new setting only when the behavior is genuinely subjective, common enough, easy to explain, and low-risk.

MeetingBar should avoid becoming a settings-heavy calendar client.

Examples:

- Fix fullscreen notification reliability before adding more fullscreen notification settings.
- Improve event details layout before adding separate toggles for every visible field.
- Improve meeting link selection priority before adding a modal "choose link" flow.
- Add diagnostics before adding refresh-rate configuration.

---

## Engineering guardrails

Keep the architecture boring and incremental.

Preferred approach:

- small, reviewable PRs;
- pure feature logic for decisions, kept in the current `MeetingBar/Core/Policies/`
  during 4.x and moved to feature folders during the 5.0 architecture migration;
- small formatters/presenters for display logic;
- side-effect services for AppKit, EventKit, UserNotifications, Keychain, network, AppleScript, and URL opening, kept behind named feature boundaries;
- Defaults reads at boundaries or through settings snapshots; the 5.0 target is `Settings/SettingsStore` + `AppSettings`;
- keep the SwiftPM logic package as a fast hostless test harness, not as a shipped core product;
- existing public behavior preserved unless the roadmap explicitly calls for a behavior change;
- add or update tests when changing risky behavior. A maintainer may ask for characterization tests around code that changes event selection, notification scheduling, refresh, or link opening.

Avoid:

- broad rewrites;
- large dependency injection frameworks;
- protocol-heavy architecture without immediate testability value;
- mixing unrelated behavior changes, localization churn, asset changes, and project settings in one PR;
- introducing new force unwraps in touched code unless the failure is impossible and documented in a comment.

A refactor that adds more concepts than it removes should be reconsidered.

### High-risk files and components

Touching these requires extra care, tests around behavior, and a small focused PR:

- `App/AppDelegate.swift`
- `Core/Managers/EventManager.swift`
- `Core/Managers/ActionsOnEventStart.swift`
- `UI/StatusBar/StatusBarItemController.swift`
- `UI/StatusBar/MenuBuilder.swift`
- `Core/Models/MBEvent.swift` and `MBEvent+Helpers.swift`
- `Core/EventStores/GCEventStore.swift`
- `Core/EventStores/EKEventStore.swift`
- `Core/Services/NotificationScheduler.swift`
- `Core/Policies/MeetingLinkDetector.swift`
- `Services/MeetingServices.swift`
- `App/Notifications.swift`

### Architecture map at a glance

Current architecture map: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

Target architecture for 5.0: [`docs/ARCHITECTURE_UPDATE.md`](docs/ARCHITECTURE_UPDATE.md).

Execution plan: [`docs/ARCHITECTURE_MIGRATION_PLAN.md`](docs/ARCHITECTURE_MIGRATION_PLAN.md).

Preferences/onboarding UI migration plan: [`docs/PREFERENCES_ONBOARDING_REDESIGN_PLAN.md`](docs/PREFERENCES_ONBOARDING_REDESIGN_PLAN.md).

For new contributors: a typical behavior change should touch one feature area and one side-effect boundary. If a change spans across `App/`, `UI/`, `Core/`, and root `Services/`, that is a signal the design needs an extracted boundary first.

---

## Release plan

### 4.12 — ship current master state

All foundation work that landed since 2026-04-23 is the 4.12 scope. No new features. Goal: ship now, write release notes, tag.

Highlights of what is in 4.12:

- crash-class force unwraps removed in `GCParser`, `MeetingServices` regex catalog, `EKEventStore` calendar lookup, `getGmailAccount`;
- failed refresh preserves last known events and calendars instead of replacing them with empty arrays;
- refresh coalescing via `throttle(200ms)` + `flatMap(maxPublishers: 1)`;
- `ProviderHealth` model published by `EventManager`, consumed by a new Status preferences tab;
- per-event `NotificationScheduler` with `mb-plan-` identifiers replaces the single-id legacy `scheduleEventNotification` path; back-to-back events no longer suppress each other;
- `GoogleCalendarPolicy` + `GoogleCalendarError` + per-calendar 403 handling so one inaccessible Google calendar does not disconnect the account;
- pure policies extracted out of historical god-structs: `EventSelectionPolicy`, `EventFilterPolicy`, `EventActionPolicy`, `MeetingLinkDetector`, `MeetingOpener`, `NotificationPlanningPolicy`, `DiagnosticsReport`;
- EventKit fetches moved off the main thread to remove menu-bar hangs on large stores;
- localization validation via `make validate-strings`;
- 135+ tests around the new policies and pipelines.

### 5.0 — architecture and modernization

Single major release. It folds the work that older notes called "4.13 / 4.14 / 4.15" into one consistent architecture rework. The architecture target is documented in `docs/ARCHITECTURE_UPDATE.md`; the execution plan is documented in `docs/ARCHITECTURE_MIGRATION_PLAN.md`.

In scope:

- wake / unlock / time-change reconcile in `NotificationScheduler` (Phase 1 close-out);
- migrate fullscreen / auto-join / on-start script from `ActionsOnEventStart` timer into the notification planner/action scheduler/action runner model (Phase 2 close-out);
- candidate-based meeting link detection with explicit source priority and scoring (Phase 3);
- localization audit so no shipped locale shows raw keys (Phase 4 close-out);
- `StatusBarPresenter` / `StatusTitleFormatter` extraction so `StatusBarItemController.updateTitle()` becomes mostly orchestration (Phase 5);
- introduce `AppSettings` + `SettingsStore` so feature logic stops reading `Defaults` directly;
- introduce a meeting provider registry so simple providers are descriptor-only additions;
- split calendar provider code into `Calendar/Providers/EventKit` and `Calendar/Providers/Google`;
- reshape the `EventStore` protocol so OAuth-only members (`signIn(forcePrompt:)`, `signOut()`) are not part of the base protocol and fetch APIs are not globally main-actor isolated;
- split notification planning, system notification reconciliation, in-app action scheduling/running, content creation, and processed-record persistence;
- introduce `AppModel`, `AppState`, `AppAction`, and `AppEnvironment` without importing AppKit/EventKit/UserNotifications/AppAuth into the model;
- reduce `AppDelegate` to composition and OS delegate wiring through coordinators;
- make the status bar controller render model-derived presentation/menu state instead of storing events;
- migrate Preferences and Onboarding into a shared `Settings/` feature so they use `SettingsStore`, provider registries, and app actions instead of direct `Defaults`, `EventManager`, and `AppDelegate` reach-through;
- preserve the test-only SwiftPM logic package for fast hostless tests and raise meaningful logic coverage toward 90-95%.

Explicitly not part of the architecture target:

- replacing `NSStatusItem` + `NSMenu` with SwiftUI `MenuBarExtra`;
- adopting `@Observable` unless the app later targets macOS 14+;
- shipping a separate `MeetingBarCore` SwiftPM product;
- a full visual rebrand outside the Preferences/Onboarding architecture migration.

Open platform decision:

- decide in a separate PR whether `MACOSX_DEPLOYMENT_TARGET` bumps 12 -> 13. The architecture must not depend on macOS 13-only assumptions.

Explicitly out of scope for 5.0 (deferred to 5.x):

- multiple Google accounts;
- Microsoft Graph / Outlook provider;
- disk snapshot cache for offline cold start;
- Google API pagination beyond `maxResults=250`;
- refresh-rate / "fashionably late" / multi-screen / cosmetic toggles.

### 5.x — providers and enterprise

Only after 5.0 ships and the new architecture has been stable in production:

- multiple Google accounts (#911);
- Microsoft Graph / Outlook provider (#590);
- re-evaluate macOS minimum to 14 only after macOS 17 ships and adoption stabilizes.

---

## macOS support policy

| MeetingBar version | macOS minimum | Notes |
|---|---|---|
| 4.x | 12.0 (Monterey) | Current shipping minimum. |
| 5.0 | 12.0 or 13.0 | Open platform decision. The architecture does not require the bump. If 5.0 drops Monterey, justify it as a support/product decision, not because of `MenuBarExtra` or `@Observable`. |
| 5.x | re-evaluate to 14 | Only after macOS 17 ships and adoption stabilizes. `@Observable` becomes a practical option only with a macOS 14+ minimum. |

Rule of thumb: support the latest three macOS versions that Apple itself maintains. Bumps cost a small fraction of users (typically 2–5% on the oldest version when Apple drops it) and let the codebase use modern APIs without availability checks.

Do not bump the deployment target inside an unrelated PR. A bump is its own PR with release-note implications.

---

## Current state on master

The scope outlined in 4.12 has landed in a series of small commits since 2026-04-23. The list below is informational for contributors who want to understand what already exists before proposing changes.

Pure policies (`Core/Policies/`):

- `EventSelectionPolicy` — `nextEvent()` decision, `71a7413`.
- `EventFilterPolicy` — `events.filtered()` decision, `71a7413`.
- `EventActionPolicy` — fullscreen / auto-join / script gate, `e3591ae`.
- `MeetingLinkDetector` — link extraction over text fields, `4d93740`.
- `NotificationPlanningPolicy` — desired notification plan, `584dc21`.
- `DiagnosticsReport` — issue-report formatter, `76abfd7`.
- `GoogleCalendarPolicy` + `GoogleCalendarError` + `AuthError: LocalizedError`, `6088956`.

Services (`Core/Services/`):

- `NotificationScheduler` — reconciles `mb-plan-` requests with `UNUserNotificationCenter`, `9da6936`.
- `MeetingOpener` — runs join script + opens meeting URL, `a03eb1e`.

Reliability and provider hardening:

- failed refresh preserves last known events/calendars, `96ca947`.
- refresh coalescing, `61938e7` followed by the throttle adjustment in `cc275f6`.
- `ProviderHealth` model and Status tab, `0031161` + `c4a07cb`, with auth classification in `6088956`.
- EventKit fetch off main, `b247236`.
- crash-class force unwraps removed, `9217bd2` + `cc275f6`.
- per-calendar 403 handling in `GCEventStore`, `6088956`.

Tooling and tests:

- `make validate-strings` checks every `.loco()` key against `en.lproj/Localizable.strings`, `fcc92b0`.
- hostless test targets so most policy tests run without launching the host app, `dbcf90a` series.
- coverage report targets, `acc215c`.

Consequence for planning: items the older roadmap had as P0.1 / P0.2 / P0.3 are now resolved or close to it. Their entries are kept below for historical context but marked done. The next active work is the close-out of Phase 1 (wake/unlock) and the start of Phase 2 (migrate `ActionsOnEventStart` into the notification plan/action architecture).

---

# Resolved blockers

These were P0 items at the previous roadmap revision. They are listed for traceability only — no further action is required unless a regression appears.

## P0.1 — Notification reconciliation regressions — done

Resolved in commits `a783d67` and `d88c3dc`.

What was done:

- `StatusBarItemController.setupDefaultsObservers()` now reconciles on changes to `.joinEventNotification`, `.joinEventNotificationTime`, `.endOfEventNotification`, `.endOfEventNotificationTime`, `.dismissedEvents`, `.preferredLanguage`, and `.hideMeetingTitle`;
- `dismissNextMeetingAction()`, `undismissMeetingsActions()`, `dismiss(event:)`, `undismissEvent(sender:)` all call `reconcileNotifications()`;
- `NotificationScheduler.buildRequest(for:event:now:)` accepts an injected `now` and uses it for `timeIntervalSince`;
- the scheduler also diffs notification content and removes/re-adds requests when title or body would change.

Open follow-up: keep test coverage growing as new Defaults are added that affect notification text or timing.

## P0.2 — ProviderHealth auth classification — done

Resolved in commits `6088956` and `0d886d7`.

What was done:

- `AuthError` conforms to `LocalizedError` with localized descriptions for `notSignedIn` and `refreshFailed`;
- `GoogleCalendarError` conforms to `LocalizedError` and `Equatable`;
- `ProviderHealth` distinguishes auth-required, stale, error, and OK states;
- `DiagnosticsReport` includes a `Provider health: …` line;
- the Status preferences tab shows a separate "Authorization required" state with a localized string.

## P0.3 — Narrow Google Calendar 403 handling — done

Resolved in commit `6088956`.

What was done:

- 401 after a forced token refresh maps to auth-required;
- 403 on a calendar's events endpoint is treated as a per-calendar forbidden error, not as account disconnect;
- forbidden calendars are skipped during fetch; events from other selected calendars still load;
- when all selected calendars fail, `ProviderHealth` surfaces the error with stale-data preserved;
- the auth state and selected calendar list are not cleared on 403.

---

# Open phases

Order is meaningful: Phase 1 close-out → Phase 2 → Phase 3 in parallel with Phase 4 → Phase 5. All of the above ships as 5.0.

## Phase 1: Reliability foundation — close-out

### What is done

See the resolved blockers above. Most of Phase 1 is in master.

### What remains

**Wake / unlock / system-time reconcile.** When the Mac wakes, the screen unlocks, the timezone changes, or system time is corrected, the app should:

1. trigger a fresh provider refresh (existing `refreshSubject.send()`);
2. force a `NotificationScheduler.reconcile` so any pending pre-sleep `UNTimeIntervalNotificationTrigger` requests are recomputed against current wall-clock time;
3. reconcile fullscreen / auto-join / script processed-events lists.

`AppDelegate` already observes `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` (used by `screenIsLocked` flag). Extend the unlock listener to call refresh + reconcile.

Also handle:

- `NSWorkspace.didWakeNotification`;
- `NSSystemTimeZoneDidChangeNotification` and `.NSCalendarDayChanged`.

### Acceptance criteria

- After 1+ hour of sleep, on wake, MeetingBar refreshes and reschedules within one refresh cycle.
- After timezone change, scheduled notification fire-times are recomputed.
- A regression test covers reconcile-on-wake by simulating a stale plan and an injected `now` that has skipped forward.

### Issues addressed

- partial: #855 system time changes.
- partial: #857 refresh/caching/network issues.

---

## Phase 2: Notification and event-action migration

### Goal

`NotificationScheduler` already owns start/end system notifications. Move fullscreen, auto-join, and on-start script onto the same planning model so all per-event actions share one source of truth, while keeping system notification reconciliation separate from in-app action scheduling/running.

### Why

Today `ActionsOnEventStart` is a 10-second polling timer that reads the next event and decides whether to fire. It works but:

- duplicates per-event dedup state in three separate `Defaults` lists;
- cannot plan for back-to-back events (only the current "next" gets considered);
- has no shared idempotency model with notification planning.

### Work items

1. Extend `NotificationPlanningPolicy` / `NotificationPlanner` to emit `fullscreen`, `autoJoin`, `scriptOnStart` plans (the model already has these `NotificationKind` cases; they are filtered out by the scheduler today).
2. Keep `NotificationScheduler` focused on system notification requests. Add a `NotificationActionScheduler` if delayed in-app action tasks are still needed.
3. Run side effects (`openFullscreenNotificationWindow`, `openMeeting`, `runMeetingStartsScript`) through `NotificationActionRunner` when a plan's fire-time arrives or when `now` already passed it during a refresh.
4. Move `Defaults[.processedEventsForFullscreenNotification]` etc. behind `NotificationRecordStore`; decide there whether to keep the existing processed-event side store or migrate to plan-identity-based dedup.
5. Once Phase 2 is complete, remove `ActionsOnEventStart`'s 10-second timer.

### Risk

This is the highest-risk change in 5.0. The current behavior is the most-tested by real users (every meeting fires it). Plan a long manual QA period and feature-flag the migration if needed.

### Acceptance criteria

- Two back-to-back events both trigger fullscreen / auto-join independently.
- Auto-join fires once per `(eventID, lastModifiedDate)` pair.
- Reschedule of an event (lastModifiedDate change) re-arms the action.
- All-day events that overlap "now" still fire fullscreen / auto-join correctly.

### Issues addressed

- #889 auto-join no longer working
- #882, #865, #830 fullscreen reliability cluster
- #859 fullscreen on external monitor
- #769 short consecutive events

---

## Phase 3: Meeting link correctness

### Goal

Opening a meeting should open the link the host intended.

### What needs to change

`MeetingLinkDetector.detect` is "first match wins" across `location → eventURL → notes → htmlTagsStripped(notes)`. That is fine for most events but fails when:

- notes contain a stale or test link that matches before the real conference data;
- a Teams event has both a `meetup-join` link and an app-only deep link;
- a Zoom URL has a password/token suffix in one field but a truncated form in another.

### Direction

Move from "first match wins" to candidate collection plus deterministic priority.

```swift
struct MeetingLinkCandidate: Equatable {
    let url: URL
    let service: MeetingService
    let source: MeetingLinkSource
    let priority: Int
}

enum MeetingLinkSource {
    case providerConferenceData
    case eventURL
    case location
    case notes
    case strippedHTMLNotes
    case customRegex
}
```

Source priority: provider conference data > event URL > location > notes > stripped HTML notes > custom regex.

Within a single source, prefer the longer URL when one is a prefix of the other (handles Zoom truncation).

### Provider integration

To enable `providerConferenceData` priority, the providers need to mark URLs as having come from structured fields:

- `GCEventStore` already parses Google `conferenceData.entryPoints[type=video]`. Surface that path through a structured field on `MBEvent` (e.g. `conferenceURL: URL?`) so the detector can score it ahead of the heuristic regex matches.
- `EKEventStore` does not have a direct equivalent. Treat `EKEvent.url` as the eventURL source unless we can detect structured conference data from EventKit metadata.

### Work items

- introduce `MeetingLinkCandidate` and `MeetingLinkSource`;
- replace `detect` with `bestCandidate`/`allCandidates`;
- update `MBEvent` to carry the chosen candidate plus alternates so the menu can offer "join with other link";
- add tests for representative cases: Teams `meetup-join` vs app-only, Zoom with password, Google Meet conference vs notes link, SafeLinks unwrapping;
- expose the custom regex tester in Preferences once the detector is candidate-based.

### Acceptance criteria

- A Google Meet event with `conferenceData` opens that URL even when notes contain a stale Zoom link.
- A Teams event with both `meetup-join` and an app-only deep link opens `meetup-join`.
- Custom regex remains as a deterministic fallback, not a layer that can override provider conference data.
- `MBEvent` is closer to data-only — no regex/URL choosing logic in its `init`.

### Issues addressed

- #847 notes link prioritized over conference link
- #873 multiple join links
- #755 incorrect Teams link detection
- #715 HTML notes invalid parsing
- #791 Zoom password/truncated links
- #901 custom regex tester

---

## Phase 4: Localization hardening

### Status

`make validate-strings` (`fcc92b0`) is in place and verifies that every `"<key>".loco()` reference in source has a matching entry in `en.lproj/Localizable.strings`.

### What remains

- audit the few places that still ship hardcoded English in `GroupBox(label:)` or other view labels (e.g. `"Provider Status"`, `"Diagnostics"` in `StatusTab`) and either keep the convention or move them all to `.loco()`;
- fix known raw-key bugs in shipped locales (#881 Korean raw keys, #867 untranslatable strings, #858 settings tabs);
- prefer English fallback over showing the raw key when a locale is incomplete.

### Acceptance criteria

- Preferences in any shipped locale never show a raw `preferences_…` key.
- CI fails when a PR adds a `.loco()` call with a key that does not exist in English.
- The validation script is part of the PR review checklist.

### Issues addressed

- #881 Korean raw keys
- #867 untranslatable strings
- #858 settings tabs broken

---

## Phase 5: Status bar and menu presentation

### Goal

Keep MeetingBar visible and make status / menu presentation safe to modify.

### Direction

Extract a `StatusBarPresenter` (or a pair: `StatusTitlePolicy` + `StatusTitleFormatter`) so `StatusBarItemController.updateTitle()` becomes mostly orchestration:

```swift
struct StatusBarPresentation: Equatable {
    let title: String
    let subtitle: String?
    let icon: StatusBarIcon
    let tooltip: String?
    let compactFallback: Bool
}
```

Pure presenter takes `events`, `nextEventState`, `Defaults` snapshot, and current locale, returns a `StatusBarPresentation`. `StatusBarItemController` only renders.

### Work items

- introduce `StatusBarPresenter` in the current policy area as an incremental step, then move it to `StatusBar/` during the architecture migration;
- migrate `updateTitle` to the new presenter;
- add unit tests for status presentation decisions (long titles, RTL, time-under-title, ongoing-event indicator);
- ensure long titles cannot make MeetingBar disappear from the menu bar — always render at least an icon fallback;
- improve event details submenu so the full title, location and notes are readable without adding many "hide field" toggles.

### Product decisions

- treat icon-not-showing and notch overflow as reliability/visibility bugs, not customization;
- hold appearance-heavy PRs (e.g. countdown color) until the presenter exists;
- avoid adding multiple appearance settings unless there is a clear, common, subjective preference.

### Acceptance criteria

- `updateTitle` is short and free of presentation logic.
- Long event titles fall back to a compact form that keeps the icon visible.
- A regression test covers RTL title rendering and time-under-title alignment.

### Issues addressed

- #914 menubar icon not showing
- #877 notch / overflow causing app to disappear
- #909 event details view does not use space
- #833 "show time under title" alignment
- #861 title alignment
- #844 timeline AM/PM format
- #874 RTL title
- #908 attendees visibility — handled via better default layout, not a per-field toggle

---

## Phase 6: Holds and explicit deferrals

These are valid user requests but should not land before the relevant earlier phase is complete.

Holds tied to provider/architecture work:

- multiple Google accounts (#848 / #911) — defer to 5.x.
- Microsoft Graph / Outlook provider (#590) — defer to 5.x.
- Google Meet PWA opener (#834) — wait until the meeting opener strategy is stable in Phase 3.
- disk snapshot cache for offline cold start — only if real users report it. In-memory preservation already covers transient failures.

Cosmetic / setting-sprawl holds:

- date on icon (#922).
- countdown color (#913).
- next-event flip preview (#905) — too complex for current status bar architecture.
- "fashionably late" notification delay (#878) — subjective workflow setting.
- show fullscreen on all screens toggle (#907) — wait until baseline fullscreen is fixed in Phase 2.
- many granular visibility toggles for attendees / location / organizer (#908) — see Phase 5 layout work.

Documentation / process:

- `docs/ARCHITECTURE.md` — current code map.
- `docs/ARCHITECTURE_UPDATE.md` — target 5.0 architecture.
- `docs/ARCHITECTURE_MIGRATION_PLAN.md` — execution plan, coverage strategy, PR sequence, and stop conditions.

---

# Open PR triage

## Merge or adapt soon

### #912 Google refresh-token checks

High priority. Reconcile with the `GoogleCalendarPolicy` + `AuthError` work already in master. The core idea is correct: do not rely on `lastTokenResponse.refreshToken` if AppAuth persists the refresh token elsewhere.

### #921 Google Meet auth account retrieval

Likely useful. Merge only with tests that fit the existing `MeetingLinkDetector` `applyMeetAuthuserIfNeeded` logic. Make sure it does not regress non-Google Meet links.

### #892 fullscreen multi-monitor fix

Useful if small and focused. Prefer a default behavior fix over a new setting. Aligns with Phase 2 fullscreen reliability close-out.

### #876 Teams icon

Low-risk cosmetic if asset quality is acceptable. Can merge after higher-priority reliability fixes or if it is truly isolated.

## Cherry-pick ideas, do not merge as-is

### #904 wake refresh / retry

Useful but broad. Take the wake/unlock refresh idea into the Phase 1 close-out. Avoid retry behavior that eventually clears state or sends noisy notifications.

### #895 / #887 EventManager race fixes

Superseded by current `master` coalescing/preservation. Check conflicts and close if obsolete.

### #812 fullscreen without links

Product decision. First stabilize fullscreen notification behavior in Phase 2. Avoid another setting unless strongly justified.

### #897 join current shortcut

Useful later. Should be built on `EventSelectionPolicy` (already extracted).

## Hold

### #899 Swift 6 / Xcode 26 / macOS 15.6

Treat as a separate platform decision. The 5.0 platform decision is 12 vs 13, not 15.6. Do not mix with reliability or architecture migration work.

### #911 multiple Google accounts

Valid user need, but too much before single-account Google reliability is solid. Defer to 5.x.

### #919 auto-open attached Google Docs

Show attachments in details first. Auto-opening docs is a subjective workflow and should not be default behavior.

### #907 show fullscreen on all screens

Setting sprawl until baseline fullscreen is fixed in Phase 2.

### #913 countdown color, #922 date on icon

Cosmetic settings. Hold.

### #905 next event flip preview

Too complex for current status bar architecture. Hold until Phase 5 presenter extraction.

---

# Definition of done

A PR is done only if it makes future work safer or improves user trust.

A good PR should satisfy at least one of these:

- reduces the number of files a contributor must understand for a common change;
- moves a rule into a tested policy or formatter;
- removes hidden global state from a flow;
- isolates a side effect behind a named service;
- preserves last known good state during failure;
- improves diagnostics for real issue reports;
- fixes a user-visible reliability bug without adding unnecessary settings.

A PR is incomplete if it:

- adds a setting without explaining why a better default is insufficient;
- changes event selection, notification, refresh, or link-opening behavior without tests;
- hides provider failure as "no events";
- makes `AppDelegate`, `EventManager`, `StatusBarItemController`, or `MBEvent` responsible for more unrelated behavior;
- mixes unrelated work (e.g. localization churn + architecture refactor in one PR);
- bumps the macOS deployment target as a side effect.

---

# Recommended next work

In execution order:

1. **Phase 1 close-out — wake / unlock / time-change reconcile.** Smallest remaining piece of Phase 1, unblocks Phase 2 manual QA. Touches `AppDelegate` lock listeners and adds a `NotificationScheduler.reconcile` call on wake.
2. **Phase 2 — start migrating `ActionsOnEventStart` into the notification plan/action architecture**, beginning with fullscreen since it has the most reliability bug reports.
3. **Phase 4 — finish localization audit** in parallel with Phase 2. Small, contained, low-risk.
4. **Phase 3 — `MeetingLinkCandidate` model.** Larger and risky; start with the candidate model and tests, leave the integration for a follow-up PR.
5. **Phase 5 — `StatusBarPresenter` extraction.** Last because it touches the highest-traffic UI path.

Architecture migration tasks should follow `docs/ARCHITECTURE_MIGRATION_PLAN.md`: coverage baseline, test harnesses, settings boundary, meeting provider registry, calendar provider separation, notification split, AppModel/coordinators, status bar renderer, then file layout cleanup. Do not rush `MenuBarExtra`, `@Observable`, or a deployment target bump as architecture side effects.

---

# Working instruction for AI agents

When starting work, an AI agent should:

1. read this `ROADMAP.md`;
2. inspect the current branch (`git status`, `git log --oneline -20`);
3. pick the next highest-priority unfinished work item under "Open phases" or "Recommended next work";
4. summarize before coding:
   - which item will be implemented;
   - which files will be touched;
   - which tests will be added or updated;
   - what behavior changes for the user.
5. make the smallest safe implementation;
6. run the relevant tests (`make test` for the full suite, `make test-logic` for hostless policy tests);
7. report back:
   - changed files and a one-line summary of each;
   - tests run and their result;
   - any deviation from the plan and why;
   - remaining risks or follow-ups.

Keep changes small and reviewable. If a single item turns out to need three sub-PRs, split it; do not attempt a single mega-commit. When a task finishes, propose the next two candidates so the maintainer can pick.
