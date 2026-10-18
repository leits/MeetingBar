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

### Codecov coverage signals

CI runs both test suites and uploads their coverage as separate Codecov flags: `swiftpm_logic` (SwiftPM LCOV) and `app_hosted` (Xcode/Slather Cobertura). The combined project coverage is still reported, but its status is **informational** because asynchronous AppKit/Combine execution can vary between runs even when production code is unchanged.

The blocking checks are:

- `codecov/project/swiftpm_logic`: zero-tolerance coverage comparison for deterministic headless policies.
- `codecov/patch`: 85% coverage target for changed coverable code, subject to careful review of untested paths.

Both coverage flags use `carryforward: false`; a missing current report should not be replaced by prior coverage. Upload errors fail the test workflow. A passing threshold does **not** substitute for failure/recovery and integration tests.

The first CI run against an older `master` cannot compare the new `swiftpm_logic` flag to a baseline. Only enforce that comparison after a `master` upload has established the same flag. When aggregate coverage drops, compare changes in covered files, flags, and timing-sensitive tests rather than adding artificial assertions to raise the percentage.

### Reviewing system-boundary patch coverage

The 85% `codecov/patch` check is a default guard, not a substitute for
test-design review. When a reliability fix touches macOS framework or external
authorization callbacks that cannot be exercised deterministically in ordinary
CI, distinguish untested *policy* from untested *platform integration*.

For any requested exception, the PR must record the **final** coverage report
(after both uploads), the uncovered production branches by subsystem, which
failure/recovery contracts are already tested, and what still requires a signed
macOS release smoke. The maintainer must explicitly accept the residual risk.
Keep `codecov/project/swiftpm_logic` blocking; do not lower the global patch
target, hide whole files, or add assertions that only increase coverage counts.
A failed required check stays failed unless an authorized branch-protection
exception is applied: documenting one does not make CI green.

The follow-up design for component/layer-aware checks is tracked in
[#1028](https://github.com/leits/MeetingBar/issues/1028). Until that is
implemented, system-boundary exceptions are exceptional and release smoke is
still required.

### Optional performance measurements

Run `make test-performance` on macOS with the pinned toolchain. `PerformanceBaselineTests` is skipped by default in the normal SwiftPM suite. Synthetic workloads cover:

- Long meeting-description link detection.
- Next-meeting selection over 5,000 events.
- Notification planning over 2,000 events.

Run on the **same** hardware to compare results, recording Xcode/Swift version, date, CPU and elapsed time. These are descriptive baselines, not hard-coded timing gates on GitHub-hosted runners; they do not measure EventKit I/O, Google API latency, real AppKit menu rendering or idle energy.

### Shareable diagnostics

`DiagnosticsReport` redacts HTTP, iCal and file URLs copied from provider errors (including calendar paths and query credentials), while keeping error types and status codes. The rest of a diagnostics report is **not** guaranteed to be free of private information; review it and any logs before pasting into a public issue.

### Release-only Google authorization smoke (real macOS + test Google account)

Run this **manually before v5 release**, not in normal automated CI. Use a non-production Google account/calendar and a signed/release-configured MeetingBar build. Record the build, macOS version, account type (no address), actions, observed behavior, and pass/fail; do not attach OAuth redirects, tokens, Keychain dumps, or unredacted calendar diagnostics.

1. **Normal authorization and persistence.** Connect Google Calendar, grant consent and select a test calendar with an upcoming event. Confirm its event/link appears; quit and reopen MeetingBar and confirm it remains connected and refreshes without a browser prompt. Reconnect when prompted and confirm new events load.
2. **Browser cancellation and abandoned callback.** From a disconnected or reconnect-required state, start Google sign-in and cancel/close the browser authorization flow before the redirect. Switch to macOS Calendar, then initiate Google sign-in again. Confirm the first attempt cannot overwrite the later selected provider, dismiss or replace the new session, or block subsequent user actions. Also try returning a redirect from the abandoned browser tab after selecting another provider; it must not change the current choice. **Record whether the original sign-in task ever settles:** generation checks prevent stale state writes but do not themselves ensure a completion callback exists.
3. **No-completion / connectivity failure.** Begin sign-in on a test network, then disconnect before Google/AppAuth returns. Confirm Calendar and menu interactions still work, switching provider remains possible, and a new explicit authorization attempt works after reconnecting. If the pending sign-in never resolves, record it as an **unresolved lifecycle failure**, not a pass. This is a manual failure probe, not a guaranteed simulation of a callback that never returns.
4. **Sign-out racing with reauthorization.** Connect the test account; start switching away from Google with sign-out and initiate a new Google connection before old token revocations finish (network throttling may help). Confirm the newer local connection is still selected and usable after the earlier sign-out settles. Quit/relaunch, refresh the test calendar and verify that Google does not unexpectedly require consent.
5. **Repeat with genuine account changes if available.** Reauthorize using a different test account. Verify a late callback or revocation from the old account does not replace the current account or erase its local state. Recheck event freshness, stale/error messaging, and the meeting URL.

**Release decision:** Any hanging authorization that blocks provider switching, unexpectedly lost new Google session, stale callback replacing a newer provider, or silent loss of last-known-good meetings is a failed smoke. Capture reproduction steps and sanitized diagnostics. Remote revocation is irreversible: a smoke run **cannot prove** safety if Google reuses an identical refresh token across separate authorizations. Treat that as a documented residual risk, not as a claim the race is fully eliminated.

Before submitting a PR, record the exact test commands and results, and distinguish tests you **ran** from tests merely recommended. If the change touches entitlements, Xcode configuration, localization, URL schemes or release signing, follow the additional checks in [ARCHITECTURE.md](ARCHITECTURE.md).

## When to add more tests

- **Bug fix:** add a regression reproducing the original failure and check the nearest realistic recovery/edge case.
- **Refactor:** add characterization coverage for existing behavior, then keep observable outputs identical unless the PR explicitly changes them.
- **New setting or action:** test its default, changed state, persistence/migration where relevant, and notification/UI invalidation paths.
- **New presentation behavior:** test policy decisions and the real rendering/layout boundary separately when geometry or native interaction changes.
- **New calendar/meeting provider:** fixture-driven parsing and error classification first; integration smoke checks for authentication or native opening remain separate.

Prefer a few tests that detect actual regressions over many fragile tests tied to implementation details.
