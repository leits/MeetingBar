# MeetingBar Development Plan: Reliability, Architecture, Fixes, Product Roadmap

## Core principle

Do not start by rewriting the app.

The app is fragile because too much behavior depends on hidden coupling between:

```text
Defaults
EventManager
StatusBarItemController
MBEvent
AppDelegate
ActionsOnEventStart
Notifications
EventKit / Google providers
```

The goal is to introduce seams gradually:

1. tests around current behavior;
2. extraction of pure policies;
3. provider state and diagnostics;
4. crash risk elimination;
5. notification scheduler;
6. meeting link engine;
7. UI/status bar cleanup;
8. larger features.

Every production behavior change needs a regression test.

---

## Current state (as of 2026-04-27)

Local branch: 9 commits ahead of `origin/master`.

Foundation work that is done — do not redo:

```text
MeetingBarTests/Helpers/BaseTestCase.swift           — Defaults snapshot/restore
MeetingBarTests/Helpers/FakeEventStore.swift         — injectable EventStore
MeetingBarTests/Helpers/FakeEvent.swift              — makeFakeEvent() factory
MeetingBarTests/EventManagerTests.swift              — provider switching, publishing
MeetingBarTests/NextEventTests.swift                 — selection logic + #864 regression
MeetingBarTests/EventFilteringTests.swift            — filter behavior
MeetingBarTests/MeetingServicesTests.swift           — link URLs + regex compile guard
MeetingBarTests/StatusBarItem/MenuBuilderTests.swift
MeetingBarTests/TimelineLogicTests.swift
MeetingBarTests/ScriptsTests.swift
MeetingBarTests/HelpersTests.swift
MeetingBarTests/GoogleCalendarParserTests.swift      — GCParser timed/all-day/malformed
MeetingBar/Core/Policies/EventSelectionPolicy.swift  — extracted from helpers
MeetingBar/Core/Policies/EventFilterPolicy.swift     — extracted from helpers
MeetingBar/Core/Models/ProviderHealth.swift          — published by EventManager
```

Closed PRs in this plan: PR 1, 2, 3, 4, 5, 6, 7, 8, 11 (see ✅ markers below).

There is no in-progress code. Working tree has:

* `MeetingBar.xcodeproj/project.pbxproj` — `+zh-Hans, +pt` regions (untracked maintenance change).
* `.claude/`, `CLAUDE.md`, `ROADMAP.md`, `dev_plan.md` — repo-side docs and tooling, not app code.

---

## Known fragility hotspots — residual (post-2026-04-27)

The CRITICAL crash classes from the original audit are closed. What remains:

| Severity | Location | Issue |
|----------|----------|-------|
| ARCHITECTURAL | `MBEvent.swift:119–136` | `MBEvent.init` runs `detectMeetingLink()` and rewrites the URL — model owns parsing. Blocker for 4.14 link engine and 4.15 attachments. |
| MEDIUM | `EKEventStore.swift:75` | `let calendar = calendars.first { $0.id == ... }!` crashes if EventKit returns an event from an unknown/deleted calendar. |
| MEDIUM | `EKEventStore.swift:147` | `try! NSRegularExpression` for Gmail account extraction. Same class as the Phase 4 fix; smaller blast radius. |
| MEDIUM | `EventManager.swift:167` | `debounce(for: .milliseconds(0))` is a no-op trampoline, not coalescing. Pick a real interval. |
| MEDIUM | `ActionsOnEventStart.swift` | Three near-identical 30-line blocks with own Defaults dedup keys; zero tests. Not a real race (single-threaded, `@MainActor`), but hard to change safely. |
| LOW | `MBEvent.swift:131` | Force unwrap on `URL(string: ... + "?authuser=...")`. Conditioned on percent-encoded value, so safe in practice. Replace when extracting link logic. |
| LOW | `GCEventStore.swift:13–15` | `Bundle.main.object(...) as! String` for Google client config. Crashes only on misconfigured build, not on user input. |
| LOW | `GCEventStore.swift:184, 207` | URL/URLComponents force unwraps on static strings. Safe today, brittle on edits. |
| ARCHITECTURAL | `EventStore` protocol | Shaped by Google OAuth (`signIn(forcePrompt:)`, `signOut()`); EKEventStore stubs `signOut` as `async {}`. Must be reshaped before adding a Microsoft Graph provider, not in parallel. |
| ARCHITECTURAL | `ProviderHealth` | Model is published by EventManager but has no consumer. Will rot without a Diagnostics view. |

---

# Phase 0: PR triage

**Do this before writing any code.** Resolve open PRs so development doesn't start on a stale base.

## Merge after review

- **#912** — Google refresh-token fix. Review test hooks, keep only what is maintainable. This is the core fix for daily reauth.
- **#892** — Primary screen fullscreen notification fix. Small, low risk, merge independently.

## Take ideas, rewrite cleanly

- **#895, #887** — Serialized refreshes and preserve last known good state. Do not merge as-is. Extract the coalescing and preservation ideas into PR 7 (Phase 3).
- **#904** — Wake/retry logic is useful, but current version returns empty on retry exhaustion. Reuse ideas only after Phase 3 preservation is in place.

## Defer until architecture exists

- **#911** — Multi-account Google. Defer until single-account reliability is solid (after Phase 5).
- **#899** — macOS/Xcode migration. Split: merge only the entitlement/permission fix (aligns with PR 17). Defer minimum macOS bump.
- **#812** — Notification feature expansion. Depends on Phase 7 scheduler.
- **#907** — Show on all screens. Depends on Phase 7 fullscreen fix.
- **#919** — Attachments. Align with Phase 11 model.

## Low priority, rebase after core work

#913, #905, #866, #893, #897, #876.

## Translations

#918, #903 — useful, but add localization validation (PR 33, Phase 10) before merging so new strings don't mask missing source keys.

---

# Phase 1: Event selection safety

## Why first

`nextEvent()` drives the visible core of the app — status bar, join button, notifications, auto-join, scripts.
Current behavior must be protected before any refactoring touches it.
Note: test helpers and some characterization tests already exist. Goal is to fill gaps and fix #864.

---

## PR 1: Expand nextEvent() characterization tests ✅

### Context

`NextEventTests.swift` and `EventFilteringTests.swift` already exist. Audit them and add missing cases.

### Must cover (add if missing)

* nearest future event selected;
* dismissed event skipped;
* declined skipped;
* canceled skipped;
* all-day skipped;
* `linkRequired` behavior;
* `.hideImmediateAfter`;
* `.showTenMinAfter` — ongoing event visible before 10 min mark, hidden after;
* `.showTenMinBeforeNext` — switches to second event logic;
* overlapping events.

### Acceptance criteria

* No production changes.
* All tests pass on current branch.
* `showTenMinAfter` test fails — this will be fixed in PR 2.

---

## PR 2: Fix #864 ✅

### Issue

Ongoing event hides before start instead of 10 minutes after start.

### Add regression tests first

```swift
test_showTenMinAfterKeepsOngoingEventBeforeTenMinutesPassed()
test_showTenMinAfterHidesOngoingEventAfterTenMinutesPassed()
```

### Fix in MBEvent+Helpers.swift

Change logic from:

```swift
event.startDate < now.addingTimeInterval(600)
```

to:

```swift
event.startDate.addingTimeInterval(600) < now
```

### Acceptance criteria

* Regression tests fail before fix and pass after.
* No unrelated changes.

---

## PR 3: Extract `EventSelectionPolicy` ✅

### Add

```text
MeetingBar/Core/Policies/EventSelectionPolicy.swift
```

### Create

```swift
struct EventSelectionSettings {
    let showEventsForPeriod: ShowEventsForPeriod
    let personalEventsAppereance: PastEventsAppereance
    let dismissedEvents: [ProcessedEvent]
    let nonAllDayEvents: NonAlldayEventsAppereance
    let showPendingEvents: PendingEventsAppereance
    let showTentativeEvents: TentativeEventsAppereance
    let ongoingEventVisibility: OngoingEventVisibility
}

struct EventSelectionPolicy {
    static func nextEvent(
        from events: [MBEvent],
        linkRequired: Bool,
        settings: EventSelectionSettings,
        now: Date
    ) -> MBEvent?
}
```

Keep old API as wrapper so callers don't change:

```swift
public extension Array where Element == MBEvent {
    func nextEvent(linkRequired: Bool = false) -> MBEvent? {
        EventSelectionPolicy.nextEvent(
            from: self,
            linkRequired: linkRequired,
            settings: .current,
            now: Date()
        )
    }
}
```

### Acceptance criteria

* Existing behavior unchanged.
* Tests call policy with fixed `now` — no real clock in tests.
* `nextEvent()` wrapper remains.

---

# Phase 2: Event filtering safety

## PR 4: Expand filtered() characterization tests ✅

### Context

`EventFilteringTests.swift` already exists. Audit and add missing cases.

### Must cover (add if missing)

* hide/show all-day events;
* show all-day only with meeting link;
* hide non-all-day without link;
* pending hide/show/inactive/underlined;
* tentative hide/show/inactive/underlined;
* declined hide/show-inactive/strikethrough;
* regex title filter;
* canceled event behavior.

### Acceptance criteria

* No production changes.
* Tests pass.

---

## PR 5: Extract `EventFilterPolicy` ✅

### Add

```text
MeetingBar/Core/Policies/EventFilterPolicy.swift
```

### Create

```swift
struct EventFilterSettings {
    let filterEventRegexes: [String]
    let allDayEvents: AlldayEventsAppereance
    let nonAllDayEvents: NonAlldayEventsAppereance
    let showPendingEvents: PendingEventsAppereance
    let showTentativeEvents: TentativeEventsAppereance
    let declinedEventsAppereance: DeclinedEventsAppereance
}

struct EventFilterPolicy {
    static func filter(
        _ events: [MBEvent],
        settings: EventFilterSettings
    ) -> [MBEvent]
}
```

Keep `.filtered()` as wrapper.

### Acceptance criteria

* Behavior unchanged.
* Tests pass.
* Filtering logic no longer reads `Defaults` directly except through wrapper.

---

# Phase 3: EventManager reliability

## Issues covered

* #900 Google Calendar reauthorization every day.
* #869 events not refreshing.
* #857 refresh/caching/network issues.
* #744 upcoming meetings disappearing.
* #845 Google account connected but no calendars.
* #739 meetings missing/stale.
* #894 calendars removed after public Google calendar 403.

---

## PR 6: Failed refresh preserves last known state ✅ (commit `96ca947` — production code; preservation tests still missing, see Active Sprint)

### Problem

Current `flatMap` error handler publishes `([], [])` on any failure. This makes transient failures look like "no events".

### Add tests

```swift
test_failedRefreshPreservesExistingEvents()
test_failedRefreshPreservesExistingCalendars()
test_failedInitialRefreshDoesNotCrash()
```

### Implementation

On refresh failure:

* keep current `calendars`;
* keep current `events`;
* store error description;
* do not publish `([], [])` if previous state exists.

### Acceptance criteria

* Existing valid state remains visible after provider failure.
* Tests pass.

---

## PR 7: Refresh coalescing ✅ (commits `69c676f`, `61938e7` — note: `debounce(0)` is a no-op, see residual hotspot)

### Problem

Three triggers exist simultaneously — Defaults changes, 3-minute timer, and manual refresh. They can all fire within milliseconds of each other (e.g., user opens Preferences and changes a calendar setting). No guard prevents concurrent refreshes.

### Implementation

Add an `isRefreshing` guard or convert to a serial `AsyncSequence`/`Actor` that drops redundant triggers while a refresh is in flight.

Simple first approach — add to EventManager:

```swift
private var isRefreshing = false

// in the sink, before fetching:
guard !isRefreshing else { return }
isRefreshing = true
defer { isRefreshing = false }
```

Or use a `CurrentValueSubject<Bool, Never>` that gates the flatMap.

### Acceptance criteria

* Concurrent triggers do not cause double-fetch.
* Manual refresh still works immediately after settings change.
* Test: rapid multiple triggers result in single fetch.

---

## PR 8: Add `ProviderHealth` ✅ (commit `0031161` — model only; no UI consumer yet)

### Add

```swift
public struct ProviderHealth: Equatable {
    public var lastSuccessfulRefresh: Date?
    public var lastAttemptedRefresh: Date?
    public var lastErrorDescription: String?
    public var isStale: Bool
    public var authRequired: Bool
}
```

`EventManager` publishes:

```swift
@Published public private(set) var providerHealth: ProviderHealth
```

### Acceptance criteria

* On success: update `lastSuccessfulRefresh`, clear error.
* On failure: preserve data, set `lastErrorDescription`.
* UI changes optional in this PR.

---

## PR 9: Calendar snapshot cache — DEFERRED

**Status (2026-04-27):** Deferred indefinitely.
In-memory preservation (PR 6) covers the realistic transient-failure case.
A disk cache introduces a new staleness mode (events from hours ago shown after wake) and adds Codable plumbing for `MBCalendar.color` (NSColor). Revisit only if user reports show "blank menu after restart" as a real pain point.

### Goal

Preserve usable events across app restart and network outage.

### Add

```text
MeetingBar/Core/Models/EventSnapshot.swift
MeetingBar/Infrastructure/EventSnapshotCache.swift
```

### Model

```swift
struct EventSnapshot: Codable {
    let calendars: [MBCalendar]
    let events: [MBEvent]
    let selectedCalendarIDs: [String]
    let provider: EventStoreProvider
    let refreshedAt: Date
}
```

If full `Codable` is blocked by `NSColor`, use a plain DTO with color as hex string.

### Behavior

* On successful refresh: write snapshot.
* On startup: load snapshot if provider matches and data is recent enough.
* On failed refresh: keep loaded/current snapshot.

### Acceptance criteria

* App shows last known events after initial network failure.
* Tests for save/load/cache invalidation.

---

## PR 10: Diagnostics menu

### Goal

Make failures visible to users and issue reporters.

### UI (add minimal surface — menu footer or Preferences tab)

* "Last updated: 08:42"
* "Google Calendar refresh failed — tap to reconnect"
* "Refresh" button
* "Copy diagnostics" button

### Diagnostics payload

* app version;
* provider;
* selected calendars count;
* last successful refresh date;
* last error description;
* macOS version.

### Acceptance criteria

* No silent empty state for provider failure.
* "Copy diagnostics" produces useful issue report text.

---

# Phase 4: Crash risk elimination

## PR 11: GCEventStore JSON parsing + MeetingServices regex safety ✅ (commit `9217bd2` — guarded casts, regex `compactMapValues`, GoogleCalendarParserTests, regex compile-guard test)

### Problem

`GCEventStore.swift` has 6+ `as!` force casts on Google API response dictionaries (lines ~336, 379, 440–452). Any schema change or unexpected field causes an immediate crash.

### Implementation

Replace all `as!` dictionary casts with `Decodable` structs or guarded `as?` with fallback/skip:

Option A — introduce `Decodable` response types:

```swift
struct GCCalendarListResponse: Decodable {
    let items: [GCCalendarListEntry]?
}
struct GCCalendarListEntry: Decodable {
    let id: String
    let summary: String?
    let backgroundColor: String?
}
```

Option B — guard every cast and log + skip on failure.

Option A is preferred if time allows; Option B is acceptable for this PR.

Also fix `MeetingServices.swift`: the 68 `try!` regex initializations should be wrapped:

```swift
// Replace:
try! NSRegularExpression(pattern: "...")
// With:
(try? NSRegularExpression(pattern: "..."))  // or assert only in DEBUG builds
```

Startup crash from a bad regex pattern is unacceptable.

### Acceptance criteria

* No `as!` on external API data in GCEventStore.
* Malformed Google API response does not crash the app.
* Bad event is skipped, error recorded in `ProviderHealth`.
* Regex initialization failures do not crash at startup.
* Tests for guarded parsing (use fake JSON payloads).

---

# Phase 5: Google Calendar provider hardening

## Issues covered

* #900, #869, #894, #845, #857, #739, #744 and future multi-account.

---

## PR 12: Fix Google refresh-token check

### Required behavior

Use persistent `OIDAuthState.refreshToken` instead of `lastTokenResponse.refreshToken`.

### Also verify

* `ensureSignedIn`;
* `forceConsent`;
* `signOut` token revocation.

### Acceptance criteria

* No daily reauth after normal token refresh.
* Unit test around auth state logic if feasible.

---

## PR 13: Typed Google API errors

### Add

```swift
enum CalendarProviderError: Error, Equatable {
    case authRequired
    case calendarAccessDenied(calendarID: String)
    case network(String)
    case rateLimited
    case invalidResponse
    case providerError(statusCode: Int, message: String?)
}
```

### Behavior

* 401 after token refresh → auth required.
* 403 on calendar events endpoint → per-calendar access denied, not account disconnect.
* 403 on auth/token endpoint → auth problem.
* 5xx/network → transient failure.
* malformed JSON → invalid response.

### Acceptance criteria

* #894 no longer disconnects the account on 403.
* Error type lets EventManager preserve state.

---

## PR 14: Per-calendar failure isolation

### Problem

One bad calendar fails the entire provider.

### Behavior

Fetch each calendar independently:

* if one calendar fails with 403, skip it and record warning in `ProviderHealth`;
* return events from other calendars;
* do not clear auth state.

### Acceptance criteria

* Test: one calendar throws access denied, another returns events — result contains valid events.
* `ProviderHealth` includes per-calendar warning.

---

## PR 15: Google pagination — DEFERRED

**Status (2026-04-27):** Deferred indefinitely.
`maxResults=250` covers all realistic users (>250 calendars or >2500 events/day is no one). No issue reports require it. Revisit if multi-account work surfaces a real overflow case.

---

## PR 16: GCParser safety ✅ (rolled into commit `9217bd2`)

### Add tests

```text
MeetingBarTests/GoogleCalendarParserTests.swift
```

Cover:

* timed event;
* all-day event;
* cancelled event;
* attendees;
* organizer;
* conferenceData URL;
* malformed event returns nil.

### Implementation

Remove remaining force unwraps from `GCParser.event()`.

### Acceptance criteria

* Malformed Google event cannot crash the app.
* Bad event skipped, error recorded.

---

# Phase 6: EventKit + ActionsOnEventStart hardening

## Issues covered

* #898 calendar permissions.
* #888 Outlook crash/hang.
* #872 main-thread diagnostics.
* #884 Teams/macOS Calendar sync issue.
* #863 app closing/hanging.

---

## PR 17: Split entitlement/permission fix

### Actions

* Ensure Calendar entitlement exists for sandboxed builds.
* Ensure macOS 14+ uses `requestFullAccessToEvents`.
* Show guidance if permission denied/unavailable.

### Acceptance criteria

* #898 addressed.
* No minimum macOS bump in same PR.

---

## PR 18: ActionsOnEventStart — refactor and tests

### Problem (corrected 2026-04-27)

`ActionsOnEventStart.checkNextEvent()` runs every 10 s on the main run loop. The class is `@MainActor`, so the original "race" framing is wrong: there is no concurrent access. The real problem is **architectural duplication**: three near-identical 30-line blocks for fullscreen / auto-join / on-start-script, each with its own `processedEvents*` Defaults key and its own ad-hoc dedup. Zero tests.

### Add tests

```swift
test_fullscreenNotificationTriggersOncePerEvent()
test_fullscreenNotificationRetriggersAfterEventReschedule()
test_autoJoinSkipsEventsWithoutLink()
test_processedEventsCleanupRemovesExpiredEvents()
```

Use a clock-injectable version or a testable policy function extracted from `checkNextEvent`.

### Refactor

Collapse the three blocks into one parameterized `processIfNeeded(action:event:offset:run:)` and let the policy decide which actions fire for a given event/now. Three Defaults keys can stay (storage compatibility) but writes go through one helper.

### Acceptance criteria

* Tests pass.
* Behavior unchanged for upgrade.
* Adding a new action type does not require copy-pasting another 30 lines.

---

## PR 19: Move EventKit fetch off main actor

### Safe first step

Wrap expensive EventKit calls in a serial actor or queue without touching `@MainActor` everywhere:

```swift
actor EventKitProviderWorker {
    func fetchAllCalendars() async throws -> [MBCalendar]
    func fetchEvents(...) async throws -> [MBEvent]
}
```

### Acceptance criteria

* No `events(matching:)` on main thread.
* No UI API called from background thread.
* Tests for mapping/parsing where feasible.

---

## PR 20: EventKit malformed event isolation

If one raw `EKEvent` is malformed:

* skip it;
* record in diagnostics;
* continue processing other events.

### Remove risks

* force unwrap on calendar matching (EKEventStore.swift line 75);
* unsafe attendee/organizer assumptions;
* `try! NSRegularExpression()` in Gmail account extraction.

### Acceptance criteria

* One bad event does not crash or hang the app.
* #888 class of issues reduced.

---

# Phase 7: Notification architecture

## Issues covered

* #889 auto-join no longer working.
* #882, #865, #830 fullscreen stopped/missing.
* #859, #809 external monitor / all screens.
* #855 system time changes.
* #769 short quick-succession events.
* #790 Esc closes fullscreen.
* #808 fullscreen without meeting link.
* #916, #879, #662, #772, #676, #757, #841, #792 various notification issues.

---

## PR 21: Notification planning tests

Add pure tests for notification planning before changing runtime behavior.

### Add

```text
MeetingBar/Core/Policies/NotificationPlanningPolicy.swift
MeetingBarTests/NotificationPlanningPolicyTests.swift
```

### Model

```swift
struct PlannedNotification: Equatable {
    let eventID: String
    let kind: NotificationKind
    let fireDate: Date
}

enum NotificationKind {
    case systemStart
    case systemEnd
    case fullscreen
    case autoJoin
    case scriptOnStart
}
```

### Tests

* one upcoming event;
* current event;
* short consecutive events;
* overlapping events;
* event without link;
* pending/tentative/declined;
* dismissed;
* custom offsets.

### Acceptance criteria

* Pure policy tests pass.
* No runtime changes yet.

---

## PR 22: Introduce `NotificationScheduler`

### Add

```text
MeetingBar/Infrastructure/Notifications/NotificationScheduler.swift
```

### Responsibilities

* schedule system notifications;
* schedule fullscreen notifications;
* schedule auto-join;
* schedule script-on-start;
* handle snooze/dismiss;
* reschedule after refresh;
* reschedule after time change/wake.

### Acceptance criteria

* Existing notification features still work.
* Scheduling does not happen from `StatusBarItemController.updateTitle()`.

---

## PR 23: Fix fullscreen notification reliability

### Includes

* fullscreen for events without links if setting enabled;
* external monitor frame correctness;
* optional show on all screens;
* Esc closes overlay;
* `collectionBehavior` uses combined options, not overwritten assignment.

### Covers

#830, #808, #859, #809, #790, #865.

### Acceptance criteria

* Testable logic covered by policy tests.
* Manual testing notes included in PR.

---

## PR 24: Fix system time / wake / unlock behavior

### Covers

#855, #857, #869 partly.

### Behavior

On wake, unlock, system time change, timezone change:

1. refresh/reconcile current events;
2. redraw status bar/menu;
3. reschedule notifications;
4. preserve cached state if refresh fails.

### Acceptance criteria

* Notifications do not remain based on pre-sleep time assumptions.
* Manual test instructions included.

---

## PR 25: Auto-join and script behavior cleanup

### Covers

#889, #711, #842, #698, #789.

### Changes

* Move auto-join into scheduler (not polling).
* AppleScript file missing → user-facing error, not crash.
* On-join script receives event payload.

### Acceptance criteria

* Auto-join works for current event.
* No `try!` crash in script folder creation.

---

# Phase 8: Meeting link detection and opening

## Issues covered

* #873 multiple join links.
* #847 notes prioritized over conference link.
* #755 Teams wrong link.
* #715 HTML notes invalid parsing.
* #791 Zoom password/truncated links.
* #901 custom regex tester.
* #885 phone numbers.
* #854 Teams browser setting.
* #803 Zoom web app.
* #834 Google Meet PWA.

---

## PR 26: Expand meeting link detection tests

### Context

`MeetingServicesTests.swift` already has 40 link URLs. Expand to cover gaps.

### Add if missing

* HTML notes parsing;
* multiple links — current behavior;
* custom regex;
* SafeLinks / URLDefense unwrapping;
* Teams `meetup-join` vs app-only links;
* Zoom with password/token;
* Google Meet conferenceData vs notes fallback.

### Acceptance criteria

* No production changes.
* Tests pass.

---

## PR 27: Extract `MeetingLinkDetector`

### Add

```text
MeetingBar/Core/Services/MeetingLinkDetector.swift
```

Move link detection out of `MBEvent.init`.

### Acceptance criteria

* Behavior unchanged.
* `MBEvent` is closer to data-only.
* Tests pass.

---

## PR 28: Candidate-based link detection

### Model

```swift
struct MeetingLinkCandidate {
    let url: URL
    let service: MeetingService
    let source: LinkSource
    let confidence: Int
}

enum LinkSource {
    case providerConferenceData
    case eventURL
    case location
    case notes
    case notesHTML
    case customRegex
}
```

### Priority order

1. provider conferenceData;
2. explicit event URL;
3. location;
4. notes;
5. custom regex fallback.

### Service rules

* Teams `meetup-join` beats app-only links.
* Zoom with password/token beats truncated link.
* Google Meet conferenceData beats random links in notes.
* SafeLinks / URLDefense unwrapped where possible.

### Covers

#847, #755, #715, #791.

---

## PR 29: Multiple link handling UX

### Covers

#873.

### Behavior

* Default to configured priority for normal cases.
* Copy/open menu shows all detected links.

---

## PR 30: Meeting opener abstraction

### Add

```text
MeetingBar/Core/Services/MeetingOpener.swift
```

* Open service in selected browser.
* Respect Teams browser setting.
* Support Google Meet PWA / Zoom web app.

### Acceptance criteria

* `MBEvent.openMeeting()` delegates to `MeetingOpener`.
* Tests for browser selection logic.

---

# Phase 9: Status bar, menu, and UI resilience

## Issues covered

* #914 menubar icon not showing.
* #877 notch overflow.
* #909 details view space.
* #908 hide attendees/location/organizer.
* #833 time-under-title alignment.
* #861 title alignment.
* #874 RTL title.
* #627 low contrast.

---

## PR 31: Extract `StatusBarPresenter`

### Add

```text
MeetingBar/UI/StatusBar/StatusBarPresenter.swift
MeetingBarTests/StatusBarPresenterTests.swift
```

### Model

```swift
struct StatusBarPresentation: Equatable {
    let title: String
    let subtitle: String?
    let icon: StatusBarIcon
    let tooltip: String?
    let compactFallbackAllowed: Bool
}
```

### Acceptance criteria

* `StatusBarItemController.updateTitle()` becomes mostly rendering.
* Presentation logic is testable without AppKit.

---

## PR 32: Compact fallback for menu bar overflow

### Covers

#914, #877.

### Behavior

* Always keep minimal visible icon/dot fallback.
* Long title never makes app disappear.

---

## PR 33: Details submenu layout

### Covers

#909, #908.

### Changes

* Full title in details, not shortened status title.
* Notes/location wrap better.
* Toggles: show/hide attendees, organizer, location, notes.

---

## PR 34: Status bar typography pass

### Covers

#833, #861, #874, #627.

* Fix baseline alignment.
* Handle RTL without swapping columns.
* Avoid low-contrast disabled text.

---

# Phase 10: Localization hardening

## Issues covered

* #881 Korean raw keys.
* #867 untranslatable strings.
* #858 broken settings tabs.

---

## PR 35: Localization validation script

### Add

```text
Scripts/validate_localizations.swift
```

or a shell/Python equivalent.

### Validate

* every `.loco()` key exists in English;
* no known typo keys;
* no missing tab titles.

### Acceptance criteria

* CI can run validation.
* Missing English key fails CI.
* Missing non-English translation warns only.

---

## PR 36: Fix known raw keys and settings strings

### Covers

#867, #858, #881.

### Acceptance criteria

* Preferences tabs show no raw keys.
* Korean/system-language fallback works.

---

# Phase 11: Attachments and meeting materials

## Issues covered

* #917, #743, #691.

---

## PR 37: Event attachments model

### Add

```swift
struct MBEventAttachment: Hashable, Sendable {
    let title: String?
    let url: URL
    let mimeType: String?
    let source: AttachmentSource
}
```

Add to `MBEvent`:

```swift
let attachments: [MBEventAttachment]
```

Parse Google Calendar `attachments[]`. Leave EventKit empty with documented limitation.

---

## PR 38: Attachments in details submenu

Show attachments section. Each attachment can be opened or copied.

### Covers

#917, #743 (Google provider; EventKit limitation documented).

---

## PR 39: Open notes/materials on join

* Open meeting only;
* open meeting + notes doc;
* open meeting + all attachments;
* ask each time.

---

# Phase 12: Automation hooks

## Issues covered

* #842, #698, #789, #504, #569, #816.

---

## PR 40: Script runner abstraction

### Add

```text
MeetingBar/Core/Services/ScriptRunner.swift
```

### Event payload (JSON file or env var)

```json
{
  "eventId": "...",
  "title": "...",
  "calendar": "...",
  "startDate": "...",
  "endDate": "...",
  "meetingUrl": "...",
  "meetingService": "...",
  "attendees": []
}
```

### Acceptance criteria

* On-join script receives event payload.
* Permission errors are user-facing, not crashes.

---

## PR 41: Event end hooks

### Covers

#504.

### Requires

Notification scheduler from Phase 7.

### Behavior

* script on event end;
* handles event changes/moves conservatively.

---

# Phase 13: Larger provider and product features

Start only after reliability and architecture foundation is complete.

## PR 42+: Google multi-account

### Covers

#448, #848.

### Prerequisites

* Google auth hardening complete (Phase 5).
* Provider errors typed.
* Snapshot/cache supports account identity.
* Calendar IDs namespaced per account.

---

## PR 43+: Microsoft Graph / Office 365 provider

### Covers

#590, #734.

Scope: new provider, not Outlook desktop scraping.

---

## PR 44+: More days / work week / custom range

### Covers

#718, #851, #893.

### Prerequisites

* Google pagination (PR 15).
* Event selection policy extracted (PR 3).
* Cache supports larger ranges (PR 9).

---

# Release roadmap

## 4.12 Reliability Foundation

Target PRs: 1–11.

Ship:

* expanded nextEvent() tests;
* #864 fix;
* EventSelectionPolicy;
* EventFilterPolicy;
* failed refresh preserves state;
* refresh coalescing;
* ProviderHealth;
* snapshot cache;
* diagnostics UI;
* GCEventStore and MeetingServices crash risk elimination;
* Google refresh-token fix.

Close/partially close:

#864, #900, #869, #845, #744, #857 partly, #894 partly.

---

## 4.13 Calendar Provider Hardening

Target PRs: 12–20.

Ship:

* Google typed errors;
* per-calendar failure isolation;
* Google pagination;
* GCParser safety;
* entitlement/permission fix;
* ActionsOnEventStart tests + Defaults race fix;
* EventKit off-main-thread;
* EventKit malformed event isolation.

Close/partially close:

#894, #898, #739, #888, #872, #884, #863 partly.

---

## 4.14 Notification Reliability

Target PRs: 21–25.

Ship:

* NotificationPlanningPolicy;
* NotificationScheduler;
* fullscreen no-link support;
* all-screens / primary-screen fix;
* Esc closes fullscreen;
* time/wake/unlock reschedule;
* auto-join cleanup.

Close/partially close:

#889, #882, #865, #830, #859, #855, #769, #790, #808, #809.

---

## 4.15 Link Engine

Target PRs: 26–30.

Ship:

* expanded link detection tests;
* MeetingLinkDetector extraction;
* candidate-based link detection;
* Teams/Zoom/HTML notes fixes;
* multiple link chooser;
* meeting opener abstraction.

Close/partially close:

#873, #847, #755, #715, #791, #901, #854.

---

## 4.16 UI and i18n

Target PRs: 31–36.

Ship:

* StatusBarPresenter;
* compact fallback;
* details submenu layout;
* hide attendees/location/organizer;
* localization validation;
* raw key fixes.

Close/partially close:

#914, #877, #909, #908, #833, #861, #874, #627, #881, #867, #858.

---

## 4.17 Meeting Materials and Automation

Target PRs: 37–41.

Ship:

* attachments model;
* attachments in submenu;
* open notes/materials on join;
* script runner abstraction;
* AppleScript args;
* event end hooks.

Close/partially close:

#917, #743, #691, #842, #698, #789, #504.

---

# Non-goals for first milestones

Do not do these early:

* full rewrite of `AppDelegate`;
* full SwiftUI migration;
* large dependency changes;
* Google multi-account before single-account reliability;
* Microsoft Graph before provider architecture cleanup;
* 5/7/14 days before pagination/cache;
* extensive UI tests before presenter extraction.

---

# Active Sprint (2026-04-27 → next)

Foundation phases 1–3 + crash-risk elimination are closed. Plan validated against actual code state on 2026-04-27 (see report in session log). Original PR ordering moved link-engine work to phase 4.14, but `MBEvent.init` doing link detection is the keystone block for everything downstream — so PR 27 promotes to next.

Order is deliberate: each item unblocks the one after it.

| # | Source PR | Status | Outcome |
|---|-----------|--------|---------|
| A1 | **PR 27 — Extract `MeetingLinkDetector`** | ✅ commit `4d93740` | `MBEvent.init` no longer parses links. `MeetingLinkDetector` is a pure policy in `Core/Policies/`. 12 unit tests. Removes the LOW `URL!` hotspot on Meet authuser. Unblocks 4.14/4.15. |
| A2 | **`EventManager` failure-path tests** | ✅ already existed | Validation gap: `FailedRefreshTests` (3), `RefreshCoalescingTests` (1), `ProviderHealthTests` (2) already cover the cases. The 2026-04-24 plan was wrong to claim they were missing. |
| A3 | **PR 10 — Diagnostics view** | ✅ commit `c4a07cb` | New `StatusTab` consumes `ProviderHealth`: color-coded state, last refresh time, last error (selectable), Refresh-now and Copy-diagnostics buttons. 10 English source keys added; Weblate will pick them up. |
| A4 | **Small residual-hotspot fixes** | ✅ commit `cc275f6` | (a) `debounce(0)` → `throttle(200ms, latest:false)` — first trigger passes through immediately, bursts collapse. (b) `EKEventStore.swift:75` `!` → guard-let with NSLog. (c) `getGmailAccount` `try!` and `Range(...)!` → guard-let. |
| A5 | **PR 18 — `ActionsOnEventStart` refactor + tests** | ✅ commit `e3591ae` | Extracted `EventActionPolicy.evaluate` + `cleanupExpired`. Three 30-line blocks → three ~12-line methods on a shared config. 10 `EventActionPolicyTests` covering window, all-day, dedup, reschedule, missing-link branches. |
| A6 | **PR 35 — Localization validation script** | ✅ commit `fcc92b0` | `Scripts/validate_localizations.sh` + `make validate-strings`. Verifies every `"<key>".loco(...)` is defined in English source strings. 274 used keys all defined; ready for CI. |

All A-track items closed 2026-04-27. Foundation is now: 91 → 101 tests, 0 `try!` regex initializations in production code, every CRITICAL hotspot from the original audit closed, and the formerly-coupled `MBEvent.init` is data-only.

B-track follow-up commit `76abfd7` closed self-review gaps: `DiagnosticsReport` extracted from StatusTab as a pure formatter (+6 tests), `getGmailAccount` regex de-greedified after a real bug surfaced from the new tests, misleading HTML-stripping test rewritten to exercise the real `htmlTagsStripped()` fallback. 113 tests total.

---

# Release strategy decision (2026-04-27)

The original ROADMAP outlined incremental 4.13 → 4.14 → 4.15 → 4.16 releases. The actual plan is now:

* **4.12 ships current `master` state.** Tag, write release notes, push. No further feature work in 4.12.
* **5.0 = single architectural + modernization release.** Folds the feature wins of former 4.13/4.14/4.15 into one major release alongside the architectural rework.
* **No new providers in 5.0.** Microsoft Graph and Google multi-account explicitly defer to 5.x. `EventStore` protocol gets reshaped in 5.0 anyway because it currently leaks Google semantics, but no second OAuth provider lands.

This trades incremental shipping cadence for a single high-trust major release. Acceptable because the 4.12 foundation is already solid and the 5.0 surface is internally coherent (notifications + link engine + MBEvent data-only + lifecycle modernization).

---

# 5.0 sprint

Order is chosen so each item lands on a stable base. Pure policies first (no runtime change), then service extractions (seams), then lifecycle/modernization (riskiest), then feature wins on the new infrastructure.

## Track 1 — pure policies (no runtime change)

| # | Item | Source |
|---|------|--------|
| **C1** | `NotificationPlanningPolicy` + tests | PR 21 |
| C2 | `MeetingLinkCandidate` model + scoring tests | PR 28 prep |

## Track 2 — service extractions (seams)

| # | Item | Source |
|---|------|--------|
| C3 | `MeetingOpener` extracted from `MBEvent.openMeeting()` | PR 30 |
| C4 | `NotificationScheduler` replaces `Notifications.swift` ad-hoc + ActionsOnEventStart timer | PR 22 |
| C5 | Wake/unlock/time-change reconciliation in scheduler | PR 24 |
| C6 | `EventKitProviderWorker` actor — fetches off main | PR 19 |
| C7 | `StatusBarPresenter` extracted from `StatusBarItemController.updateTitle` | PR 31 |

## Track 3 — modernization

| # | Item | Notes |
|---|------|-------|
| C8 | Bump `MACOSX_DEPLOYMENT_TARGET` 12 → 13 | Drop `if #available(macOS 14, *)` branches except calendar API which still needs the dual path. ~2-3% user loss; macOS 12 is EOL from Apple. |
| C9 | Adopt `Observation` framework (`@Observable`) for `EventManager` | Requires macOS 13.4+. Drops `ObjC bridging cost` of `ObservableObject`. |
| C10 | `AppDelegate` → SwiftUI App lifecycle with `Settings { }` scene | Risky. Do after C4/C7 so notification + status bar are extracted first. |
| C11 | Evaluate `MenuBarExtra` to replace `StatusBarItemController` + `MenuBuilder` | Only if it doesn't regress accessibility, RTL, or notch overflow handling. May stay as NSStatusItem. |
| C12 | `EventStore` protocol reshape | Remove Google-only `signIn(forcePrompt:)`, `signOut()` from protocol. Move to a `OAuthProvider` extension. EventKit stops stubbing. |

## Track 4 — feature wins on new infrastructure

| # | Item | Source |
|---|------|--------|
| C13 | Fullscreen reliability (Esc, multi-screen, no-link events) | PR 23 |
| C14 | Auto-join cleanup, on-join script payload | PR 25 |
| C15 | Candidate-based link detection w/ priority + scoring | PR 28 |
| C16 | Multiple-link UX in menu | PR 29 |
| C17 | Generic attachment model + Google attachments parsing | PR 37 |
| C18 | Attachments in details submenu | PR 38 |
| C19 | Status bar typography & details layout | PR 33, PR 34 |

## Explicitly deferred to 5.x

* PR 42 Google multi-account
* PR 43 Microsoft Graph provider
* PR 44 More days / work-week views
* PR 9 disk snapshot cache (still doesn't justify itself)
* PR 15 Google pagination

## Execution order

C1 → C2 → C3 → C4 → C5 → C6 → C7 → C8 → C9 → (decision: C10/C11) → C12 → C13–C19.

Track 1 is starting now: **C1 — `NotificationPlanningPolicy` + tests**.

After A1–A6, choose between:

* **Phase 4.13 NotificationScheduler track** (high user-visible value but big surface) — PRs 21–25.
* **Phase 4.14 Link engine track** (now unblocked by A1) — PRs 28–30.

Recommendation: do A1–A6 in order, then ship a 4.12 release, then start 4.13.

## Deferred / dropped from earlier plan

* **PR 9 disk snapshot cache** — adds a worse staleness mode than blank-on-cold-start; in-memory preservation is enough.
* **PR 15 Google pagination** — no real users hit the limit.
* **PR 12 Google refresh-token fix** — keep; adopt #912's idea, but re-evaluate after A1–A4 since AppAuth migration may have changed the failure mode.
* **EventStore protocol reshape** — required *before* PR 43 (Microsoft Graph), not in parallel. Add as prerequisite to phase 13.

---

# Original first-milestone block (kept for reference)

```text
Milestone: 4.12 Reliability Foundation (snapshot 2026-04-24)

PR 1 ✅ expand nextEvent() characterization tests
PR 2 ✅ fix #864 with regression tests
PR 3 ✅ extract EventSelectionPolicy
PR 4 ✅ expand filtered() characterization tests
PR 5 ✅ extract EventFilterPolicy
PR 6 ✅ failed refresh preserves state (tests still pending — see A2)
PR 7 ✅ refresh coalescing (debounce(0) bug — see A4)
PR 8 ✅ ProviderHealth (no consumer — see A3)
PR 9 — snapshot cache: DEFERRED
PR 10  diagnostics UI: A3
PR 11 ✅ GCEventStore + MeetingServices crash risk elimination
PR 12  Google refresh-token fix: revisit after A4
```
