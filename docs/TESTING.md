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

### Layer-aware Codecov coverage checks

CI runs the SwiftPM logic and macOS app-hosted suites separately. Their reports
are exported before upload, and **both are validated** by
`Scripts/verify_coverage_reports.sh` (self-tested by
`Scripts/test_verify_coverage_reports.sh`). Missing/empty reports fail
`Build and Test`. On trusted builds, a missing `CODECOV_TOKEN` also fails CI.
Fork PRs without access to this secret can still run tests but cannot publish
Codecov reports; maintainers must verify coverage checks on a trusted revision.

Both coverage flags set `carryforward: false`. Uploads occur **after both test
suites complete**, and `codecov.notify.after_n_builds: 2` prevents the misleading
SwiftPM-only provisional statuses we previously saw. Two uploads per commit are
expected; if the number changes, the notification count must change too.
Code coverage and successful uploading are separate contracts: a green test
run does not imply that Codecov processed both uploads.

| Check | Threshold | Behavior | Ownership |
| --- | --- | --- | --- |
| `codecov/project/swiftpm_logic` | No decrease from base | Blocking | SwiftPM logic baseline |
| `codecov/patch/domain_logic` | 85% | Blocking | Every source compiled into the `MeetingBarLogic` target from `Package.swift` |
| `codecov/patch/app_workflows` | 75% | Blocking | Explicit app-hosted policy/orchestration files listed under `paths` in `codecov.yml` |
| `codecov/patch/default` | 85% reference | Informational | All changed coverable production code, including system boundaries |
| `codecov/patch/app_integration` | 85% reference | Informational | All app-hosted sources; useful for examining external-framework gaps |
| `codecov/project/default` | Comparison to base | Informational | Combined project trend |

The app-workflow list currently includes `AppModel`, `CalendarRepository`,
`CalendarSync`, `GoogleCalendarDataReader`, `MeetingOpener`,
`NotificationScheduler`, `PreferencesPresentation`, and `AppSettings`.
They have injectable seams and can be tested without real calendar accounts or
fragile macOS UI automation. The 75% gate is a patch threshold rather than a
claim that the whole app is 75% covered.

AppAuth browser/Keychain, EventKit queries and permissions, and SwiftUI/AppKit
rendering remain in the **informational** patch view. This is not permission to
ship untested behavior: reviewer expectations still include deterministic tests
for extractable policies and adapters, explicit failure/recovery scenarios, and
signed macOS release smoke for platform effects. When one file mixes decision
logic with an untestable framework boundary, prefer a small policy extraction
and contract test over lowering a threshold or ignoring the whole file.

**When code moves:** Add new pure logic to `Package.swift` so the SwiftPM
patch gate covers it automatically. If a new app-layer coordinator can be tested
with fakes, add its path to `app_workflows` in the same PR as the production
change. Reviewers should examine the informational aggregate patch on every
PR for uncovered critical branches outside these two enforceable sets.

**Repository protection:** Require `Build and Test`,
`codecov/project/swiftpm_logic`, `codecov/patch/domain_logic`, and
`codecov/patch/app_workflows` in GitHub branch protection, replacing
`codecov/patch` if it was previously required. Check names must be confirmed
from a complete two-upload run before changing the required status list.
GitHub App access may not allow updating branch rules; a maintainer must
perform and verify this step. Do not assume `codecov/patch/default` is blocking:
it is an explicitly informational diagnostic.

If a blocking logic or app-workflow patch fails, add meaningful tests or review
the boundary; do not add coverage-only assertions. A narrowly documented
exception still requires explicit maintainer approval and authorized branch
protection handling, not a global threshold change.

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
