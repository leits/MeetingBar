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
- `App/AppModel.swift`
- `Calendar/EventManager.swift`
- `Calendar/CalendarRepository.swift`
- `Calendar/Providers/EventKit/EventKitEventStore.swift`
- `Calendar/Providers/Google/GoogleCalendarEventStore.swift`
- `Calendar/MBEvent.swift`
- `Meetings/MeetingLinkDetector.swift`
- `Meetings/MeetingOpener.swift`
- `Meetings/MeetingProvider.swift`
- `Notifications/NotificationScheduler.swift`
- `UI/StatusBar/StatusBarItemController.swift`
- `UI/StatusBar/MenuBuilder.swift`
- `App/Notifications.swift`

### Architecture map at a glance

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) is the canonical map of
the current code.

For new contributors: a typical behavior change should touch one feature
area and one side-effect boundary. If a change spans across `App/`,
`StatusBar/`, `Calendar/`, and `Meetings/`, that is a signal the design
needs an extracted boundary first.

---

## Release plan

### 5.0 — shipped (architecture rework)

5.0 is an internal architecture rework with no user-visible behavior changes.
Goal: future bug fixes and provider additions touch one feature folder
instead of several. The full layout lives in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md);
the user-facing release notes live in [`CHANGELOG.md`](CHANGELOG.md).

Highlights of what landed:

- Reliability: failed refresh preserves last known events/calendars; refresh
  coalescing via `throttle(200ms)` + `flatMap(maxPublishers: 1)`; EventKit
  fetches off main; per-calendar Google 403 handling; wake/unlock/timezone
  observers trigger refresh + notification reconcile; per-event
  `NotificationScheduler` with stable `mb-plan-` identifiers replaces the
  legacy single-id path.
- State: `AppModel` / `AppState` / `AppAction` / `AppEnvironment` (single
  file) own app state; `AppSettings.current` is the single Defaults
  boundary; `MenuBuilder` reads a `StatusBarMenuState` value type with zero
  direct Defaults reads.
- Feature folders: `Calendar/`, `Meetings/`, `Notifications/`, `StatusBar/`,
  `Settings/`, `Preferences/`, `Onboarding/` at the project root. `Core/` is
  gone. `MeetingProvider.all` is a single struct array — adding a new
  meeting service is one descriptor entry.
- Tests: 181 hostless logic tests at 95.9% coverage, plus the host suite.

Explicitly **not** part of 5.0:

- replacing `NSStatusItem` + `NSMenu` with SwiftUI `MenuBarExtra`;
- adopting `@Observable` (would need macOS 14+);
- shipping a separate `MeetingBarCore` SwiftPM product;
- a full visual rebrand;
- bumping `MACOSX_DEPLOYMENT_TARGET` (still 12.0).

Deferred to 5.x:

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

## Holds and explicit deferrals

These are valid user requests but explicitly held — either because they
depend on 5.x provider work or because they are setting-sprawl that the
product principles push back on.

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

5.0 architecture is complete. Suggested order for the next batch of
work, ranked by user impact and risk:

1. **Open-PR triage** above — high-priority items in the "Merge or adapt
   soon" group (#912 Google refresh-token, #921 Meet account retrieval,
   #892 fullscreen multi-monitor, #876 Teams icon).
2. **Localization gaps** — fix known raw-key reports (#881 Korean,
   #867 untranslatable strings, #858 settings tabs) as small focused PRs.
3. **5.x provider work** when there is appetite — multiple Google accounts
   (#911), Microsoft Graph / Outlook (#590). These are weeks-long projects;
   start by sketching the provider boundary and then plan from there.
4. **Modernization decisions** — macOS 12 → 13 bump and SwiftUI App
   lifecycle / `MenuBarExtra` / `@Observable` evaluation. Treat each as a
   separate PR with release-note implications. Do not roll them into
   feature work.

Future architecture work should preserve the 5.0 boundaries: `AppModel`
owns state, `AppSettings.current` is the single Defaults boundary, feature
folders stay flat, and the hostless logic package keeps its 95%+ coverage.

---

AI-agent operating instructions live in [`AGENTS.md`](AGENTS.md) and
[`CLAUDE.md`](CLAUDE.md).
