# Testing MeetingBar

This is the contributor-facing guide for choosing and writing tests. See [ARCHITECTURE.md](ARCHITECTURE.md) for component ownership and the policy/adapter design, and [PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md) for product invariants.

## Principle: test the behavior at the lowest useful layer

MeetingBar is trusted precisely when a meeting is about to start. Protect correctness, recovery and user-visible behavior rather than maximizing the number of assertions or tests. Prefer small, deterministic suites, with selective integration coverage for wiring that unit tests cannot see.

| Layer | Where | Typical subjects |
| --- | --- | --- |
| **Hostless logic** | `MeetingBarLogicTests/` via `make test-logic` | Event eligibility/selection, link candidate detection, URL cleanup, notification plans, Google policies, status-bar title/icon/presentation decisions |
| **App-hosted** | `MeetingBarTests/` via `make test-app` | Provider adapters and calendar refresh, `AppModel` actions, settings propagation, `MenuBuilder`, notification reconciliation, AppKit layout and native interaction |
| **Manual macOS verification** | Real, preferably release-configured app | EventKit permission prompts, Google OAuth, installed meeting apps, screen/notch/VoiceOver behavior, signed distributions and upgrades |

`make test` runs both automated suites. The app-hosted suite needs Xcode/macOS; SwiftPM logic tests are intentionally independent of a launched app. These are complementary layers, not three copies of the same test matrix.

## Writing useful tests

1. **Start with the user-visible failure or invariant.** State what should be selected, displayed, opened, retained, notified, or explained after the triggering action.
2. **Pick the owner and boundary.** Test a pure decision in its policy. Test a `CalendarSync`, `AppModel` or scheduler workflow with its fake provider/sink. Add an integration test only if real wiring or rendering is part of the risk.
3. **Control the inputs.** Use fixed `Date` / injected clock, event factories, stable identifiers, fixture payloads, fake providers, in-memory publishers and recording sinks.
4. **Assert outcomes, not implementation choreography.** Favor chosen event, published health state, pending plan, opened URL, accessible content or final geometry over method-call counts and private helper details.
5. **Cover a failure case and recovery.** A successful first fetch is insufficient if the bug occurs on timeout, provider switch, stale result, lost permission, repeated reconcile or reauthorization.
6. **Keep tests isolated.** Restore `Defaults`, clean up observers/tasks, avoid shared mutable fixtures, and never depend on test order or live accounts.
7. **Make asynchronous behavior deterministic.** Prefer controlled publishers and suspended fake sinks with explicit continuation/release over arbitrary sleeps. Prove cancellation/order where they affect the result.
8. **Avoid duplicate matrices.** Fully exercise branches at policy level, then use a few app-hosted scenarios to prove adapters, observers and menu/notification wiring carry the decision through.

### High-value regression contracts

| Area | Example questions a test should answer |
| --- | --- |
| Selection/filtering | Which event wins among overlapping, ongoing, dismissed, declined, pending or soonest-future events? What happens at day/time thresholds? |
| Calendar freshness | Does a failed refresh preserve the last usable events and surface the right stale/auth/permission state? Can a previous provider publish late results after switching? |
| Google/EventKit | Are pages read completely? Are per-calendar forbidden errors distinguished from account auth failures? Are malformed/missing fields handled without a crash? |
| Link detection/opening | Does native conference data win over unrelated notes? Are SafeLinks and meeting passwords preserved? Does fallback open only once? |
| Notifications | Does repeated reconcile change nothing? Are obsolete requests removed, new ones added, and delayed actions cancelled when settings/dismissals change? |
| Status bar | Does the policy choose the right title/icon/fallback? Does the actual stacked view fit, resize and preserve native hit testing and accessibility? |
| Settings/migrations | Does changing a preference trigger the intended refresh or reconciliation once? Is old persisted data migrated without loss? |

## Fakes, fixtures and host tests

- Use existing helpers in `MeetingBarTests/Helpers/`, `BaseTestCase`, `FakeEventStore`, and `AppModelTestHarness` before introducing a new harness.
- A pure policy file belongs in the SwiftPM `MeetingBarLogic` sources listed in `Package.swift`, with tests in `MeetingBarLogicTests/`. Keep the corresponding `+MeetingBar` adapter in the app target, as described in the architecture guide.
- Exercise real app-target mapping where it is the source of risk: a perfect hostless detector test cannot catch a broken `MBEvent` adapter, for example.
- Integration tests with `NSMenu`, `NSStatusBarButton`, fake notification sinks or laid-out `NSView` hierarchies are valuable when those interfaces are the behavior under test. A presentation-model assertion alone does **not** prove visual geometry, native click routing or View accessibility.
- Geometry/hit-test assertions still cannot substitute for real active/inactive displays, notched menu bars, VoiceOver and mouse behavior. Capture those manual gaps explicitly in PR notes.
- Avoid routine tests against real Google accounts, EventKit databases, network availability, wall-clock scheduling or screenshots rendered across arbitrary macOS environments.

## Running and interpreting checks

```sh
make test-logic       # Fast SwiftPM hostless tests + coverage report
make test-app         # Xcode app-hosted tests + coverage report
make test             # Both suites
make coverage-report  # Reports after the respective suites have run
make lint
make validate-strings
```

`make coverage-gate` currently **reports** whether hostless coverage reaches 90%; it does not fail below that threshold. CI can separately enforce Codecov project/patch checks. High coverage of pure policies does not establish integration, lifecycle, layout or signed-build confidence.

Before submitting a PR, record the exact test commands and results, and distinguish tests you **ran** from tests merely recommended. If the change touches entitlements, Xcode configuration, localization, URL schemes or release signing, follow the additional checks in [ARCHITECTURE.md](ARCHITECTURE.md).

## When to add more tests

- **Bug fix:** add a regression reproducing the original failure and check the nearest realistic recovery/edge case.
- **Refactor:** add characterization coverage for existing behavior, then keep observable outputs identical unless the PR explicitly changes them.
- **New setting or action:** test its default, changed state, persistence/migration where relevant, and notification/UI invalidation paths.
- **New presentation behavior:** test policy decisions and the real rendering/layout boundary separately when geometry or native interaction changes.
- **New calendar/meeting provider:** fixture-driven parsing and error classification first; integration smoke checks for authentication or native opening remain separate.

Prefer a few tests that detect actual regressions over many fragile tests tied to implementation details.
