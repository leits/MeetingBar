# MeetingBar — Project Context

This document provides long-lived product and engineering context for people and coding agents working on MeetingBar. It is independent of any AI tool, task, branch, or release cycle.

**Authority:** The checked-out source code and tests are authoritative for current behavior. Use [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for implementation details, [`CONTRIBUTING.md`](CONTRIBUTING.md) for contributor workflow, and `Makefile` / CI workflows for validation commands. Do not assume that an issue, PR, proposal, or this document accurately describes the current branch without verification.

## Product

[MeetingBar](https://github.com/leits/MeetingBar) is a free, open-source macOS menu-bar app that shows a user's current or next calendar meeting and provides quick ways to join, inspect, or prepare for it. It reads Apple Calendar through EventKit, and Google Calendar and Microsoft 365 through direct integrations. The app also supports meeting-service links, reminders, shortcuts, and automation.

### Core promise: a trustworthy meeting entrypoint

- **Right meeting:** Select the correct current/next event according to user settings and event status.
- **Fresh information:** Refresh reliably; preserve the last known usable calendar state across transient provider failures.
- **Explicit failure states:** Never treat missing permissions, lost authorization, failed refresh, or stale data as an ordinary empty calendar.
- **Visible and usable:** Keep the menu-bar entrypoint useful within native macOS layout and interaction constraints; degrade gracefully where possible.
- **Correct action:** Detect and open the intended meeting URL, preserving required parameters and using predictable browser/native-app fallbacks.

MeetingBar is a small, native-feeling macOS utility, not a general-purpose calendar client or meeting workspace. Simplicity and reliable defaults matter more than an ever-growing set of preferences.

### Product decision rules

1. Prioritize reliability and correctness, then regression protection, maintainability, product improvements, and finally visual polish.
2. Prefer fixing common behavior for everyone over exposing a preference for a narrow edge case.
3. Add settings only when there is a meaningful, recurring user choice that is understandable and worth maintaining.
4. Preserve backward compatibility, including existing preferences and saved user data, unless a deliberate migration is part of the change.
5. Evaluate feature proposals separately from implementation quality: a technically sound PR is not necessarily the right product decision.
6. Avoid expanding feature scope or architecture without a concrete benefit to users or maintainability.

The primary maintainer is Andrii Leitsius. Development and review time are limited; favor focused, reviewable contributions over ambitious rewrites.

## Engineering map

MeetingBar uses Swift, AppKit for the macOS status bar, SwiftUI for application screens, EventKit, and direct Google Calendar and Microsoft Graph integrations. The main app is built with Xcode. `Package.swift` defines a separate hostless `MeetingBarLogic` testable module for pure policies.

The following is an orientation map, **not** a substitute for reading the current code:

| Area | Current seams | Responsibility |
| --- | --- | --- |
| Lifecycle and OS wiring | `MeetingBar/App/AppDelegate.swift`, `LifecycleObserver.swift`, `WindowCoordinator.swift` | App initialization, lifecycle, system events and windows. |
| Application state and action routing | `MeetingBar/App/AppModel.swift` (`AppState`, `AppAction`, `AppEnvironment`) | UI actions, observable state, injected side-effect boundaries and workflow coordination. |
| Calendar providers | `MeetingBar/Calendar/EventStore.swift`, `CalendarRepository.swift`, `Providers/` | Provider-neutral calendar access with EventKit, Google and Microsoft 365 adapters. |
| Refresh and health | `MeetingBar/Calendar/CalendarSync.swift`, `ProviderHealth.swift` | Refresh orchestration, provider switching, cancellation, last-good data and error/permission state. |
| Event selection/filtering | `MeetingBar/Calendar/EventSelection.swift`, `EventFiltering.swift`, `+MeetingBar` adapters | Pure choices about which events are eligible and which one to display/join. |
| Event representation | `MeetingBar/Calendar/MBEvent.swift`, `MBEvent+MeetingBar.swift`, `MBCalendar.swift` | Normalized data from different providers and app-specific mappings. |
| Meeting links and opening | `MeetingBar/Meetings/MeetingLinkDetector.swift`, `MeetingProvider.swift`, `MeetingOpener.swift` | Detect, rank and normalize candidates; execute meeting-opening actions separately. |
| Notifications and timed actions | `MeetingBar/Notifications/NotificationPlanner.swift`, `NotificationScheduler.swift`, `NotificationActionRunner.swift` | Plan notifications, reconcile OS requests and own delayed/fullscreen/auto-join/script actions. |
| Status bar and menu | `MeetingBar/UI/StatusBar/StatusBarPresentation.swift`, `StatusBarItemController.swift`, `StatusBarStackedTitleView.swift`, `MenuBuilder.swift` | Compute presentation separately from AppKit rendering and native interaction. |
| Settings | `MeetingBar/Settings/AppSettings.swift`, `Extensions/DefaultsKeys.swift` | Persistent preferences and explicit snapshots for policies/workflows. |

### Architectural conventions

- **UI triggers actions; `AppModel` coordinates; feature owners manage workflows; pure policies decide; adapters perform OS and network effects.**
- Preserve the existing *policy + `+MeetingBar` adapter* pattern where it is useful: decisions depend on explicit inputs such as `settings` and `now`, while app-specific mappings and `Defaults` reads live at boundaries.
- Keep policies free of direct dependencies on AppKit, EventKit, UserNotifications, provider SDKs and networking, Keychain, AppleScript, and persistent settings.
- Avoid treating `Defaults` as implicit dependency injection or a general-purpose event bus. Do not add a broad settings abstraction where the existing snapshot pattern suffices.
- Every recurring/delayed asynchronous workflow needs a clear owner and cancellation path. Check stale-result protection when providers or settings change.
- Do not introduce a new abstraction or coordinator merely to follow a pattern; it must isolate a decision, an integration, or an owned workflow.

## High-risk behavior and regression boundaries

### Calendar freshness and providers

A failed refresh must not silently erase previously valid meetings. Account authentication failures, per-calendar access failures, missing EventKit read permission, connectivity problems, and genuinely empty results must remain distinguishable. When changing provider operations, examine refresh serialization, timeout/cancellation, provider switching, token persistence and stale-result publication.

### Selection and filtering

Current/next selection affects the status-bar title, menu join target, notification planning, scripts and automation. Test ongoing and overlapping events, soonest-upcoming ordering, all-day and declined/canceled events, pending/tentative handling, dismissals, link requirements, day boundaries and time thresholds. Use an explicit fixed clock.

### Meeting-link detection and opening

Calendar invites can contain multiple links, wrapped enterprise redirect URLs, HTML notes and provider-specific conference data. Preserve source precedence and meeting tokens (for example Zoom passwords), reject malformed candidates safely, and avoid accidentally launching the wrong service or opening twice. Detection and execution should stay separate.

### Notifications and delayed actions

Notification planning should be deterministic; scheduling should reconcile the desired state against the OS and remain idempotent. Repeated refresh, dismissal, settings changes, sleep/wake, overlapping and back-to-back meetings must not lose alerts or trigger actions twice. Test cancellation and ordering around asynchronous operations.

### Status bar and native macOS behavior

The status item must remain useful under long titles, small available menu-bar width, stacked/inline layouts, different display configurations, light/dark and active/inactive appearances. Test both presentation decisions and AppKit layout/geometry, native click handling and accessibility. Programmatic geometry tests cannot replace all manual multi-display and VoiceOver checks.

### Compatibility-sensitive changes

Treat settings migrations, localization keys, automation/AppleScript contracts, URL schemes, dependencies, `Info.plist`, entitlements, Xcode project configuration, signing and installation behavior as high-risk even if a change looks small.

## Testing approach

| Test layer | Location / command | Best for |
| --- | --- | --- |
| Hostless unit tests | `MeetingBarLogicTests/`; `make test-logic` | Pure filtering/selection, URL handling, provider policies, planning and presentation decisions. |
| App-hosted tests | `MeetingBarTests/`; `make test-app` | State/action wiring, provider adapters, fakes for refresh and notification sinks, menu construction, AppKit behavior, migrations. |
| Combined verification | `make test` | Both suites; also run targeted commands from `Makefile` and CI for the affected files. |
| Manual macOS checks | Relevant behavior on a real Mac | Real calendar permissions/OAuth, installed native meeting apps, status item visibility, accessibility and signed distribution behavior. |

- Default to deterministic tests with fixture data, fake providers/sinks and fixed time. Avoid network-dependent or real-calendar tests as routine CI coverage.
- Put a rule's edge cases in the lowest level that can exercise them accurately. Add a smaller number of integration tests to verify wiring and state propagation; do not duplicate whole matrices at every layer.
- Protect both successful behavior and failure recovery. For a refactor, add characterization tests before moving behavior.
- Coverage is a signal, not a quality target by itself. Favor tests that fail for meaningful regressions over tests that merely exercise lines or mock implementation details.
- Be precise about verification: passing CI does not prove actual multi-display appearance, real accessibility behavior, OAuth callback handling or signed builds.

## Working with changes and contributions

1. Locate the existing owner of the behavior and trace inputs, settings changes, events and side effects before editing.
2. Distinguish the root cause from the visible symptom, including recovery and stale/error-state behavior.
3. Choose the smallest change that fixes the real problem without introducing hidden coupling or extra preferences.
4. Identify the regression surface and write targeted tests at the appropriate layer.
5. Keep PRs coherent. Separate independent features, broad refactors and release-sensitive configuration changes.
6. In reviews, distinguish merge blockers from optional follow-up work and say what was actually verified.
7. When adapting a contributor's work, preserve authorship and original commit history where practical; do not silently replace credit.

Contributor feedback should be clear and specific, respectful without unnecessary formalism. An issue or open PR is evidence of a proposal or report, not proof that a behavior is desired or a change should be merged.

## Reference documents

- [README](README.md) — product overview and user installation.
- [Architecture](https://github.com/leits/MeetingBar/blob/master/docs/ARCHITECTURE.md) — detailed current component map, ownership and integration flows.
- [Contributing](https://github.com/leits/MeetingBar/blob/master/CONTRIBUTING.md) — contributor setup and validation.
- [Makefile](Makefile) and [CI workflows](.github/workflows) — executable validation definitions.
- [GitHub Releases](https://github.com/leits/MeetingBar/releases) — published version notes; check relevant tags/branches rather than assuming a particular release state.

Do not copy detailed code trees, package versions, issue lists, build numbers, coverage figures, or release snapshots into this file. Verify such details in the current repository when needed.