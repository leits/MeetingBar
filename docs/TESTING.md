# Testing MeetingBar

## Pull request checks

- make test-logic-quiet: SwiftPM pure-logic and policy tests.
- make test-app-quiet: macOS app-hosted tests, provider contracts, NSMenu/status-bar layout and application flows.
- make lint: SwiftLint.
- CI runs both targets and uploads SwiftPM LCOV plus app-hosted Cobertura coverage. Coverage is a diagnostic signal, not a substitute for meaningful regression tests.

Provider tests should cover external input -> production parser/adapter -> domain result and error/recovery. They do not contact real Google, require OAuth credentials, or read a user's EventKit calendars. App flow tests replace outward side effects and verify meeting selection, freshness, join target and notifications.

## Performance baselines

Run make test-performance on macOS with the repository's pinned toolchain. This enables PerformanceBaselineTests (skipped by default CI). Synthetic baselines include:

- Long meeting-description link detection.
- Next-meeting selection across 5,000 events.
- Notification planning across 2,000 events.

Record Xcode/Swift version, hardware, date, wall time and CPU utilization for each run. Compare with results on the same hardware; do not impose hard-coded latency thresholds on shared runners. These tests do not measure EventKit I/O, Google network, AppKit rendering or idle battery drain.

Long-running app energy/memory checks need separate controlled Instruments sessions; the live-system validation phase remains outside the automated testing program.

## Diagnostics privacy

Shareable diagnostics redact HTTP, iCal and file URLs in provider error strings while preserving failure types and HTTP statuses. This is not a general personal-data scrubber. Review logs and diagnostic text before posting them publicly.
