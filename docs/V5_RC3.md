# MeetingBar 5.0.0 RC3 preparation

This is a candidate integration, not a published or signed release. Review and merge the focused PRs first, then refresh this branch against master so the release PR contains only the build-number change and this document.

## Candidate identity

- Marketing version: `5.0.0`.
- Build number: `172` (Debug and Release), incremented from RC2's 171.
- Proposed tag: `v5.0.0-rc3`; absent when checked on 2026-10-12.
- The existing `v5.0.0` tag identifies RC1. Do not move it. Decide the stable release version separately before publishing stable.
- No tag, release, signing credentials, provisioning configuration or published assets are changed by this PR.

## Included candidates

| Change | PR | Reviewed integration input |
| --- | --- | --- |
| Stacked status title | [#1004](https://github.com/leits/MeetingBar/pull/1004) | `4ee7c0c6a5c91349e2292c58955528a36c134283` |
| Clari | [#1005](https://github.com/leits/MeetingBar/pull/1005) | `4c6e92688ca9b6af101922f06056cc27fd100a06` |
| Tuple | [#1001](https://github.com/leits/MeetingBar/pull/1001) | `308e33dcbead276c1ed1975f85f8009d484aeed8` |
| Hide now | [#1006](https://github.com/leits/MeetingBar/pull/1006) | `5e0019118dbbebba0a0057f72f7d099e2eaa7a5b` |
| Event-start scripts | [#1007](https://github.com/leits/MeetingBar/pull/1007) | `4349384d93fa75562a8c24e49a617968f50b2ce0` |
| Translations | [#1008](https://github.com/leits/MeetingBar/pull/1008) | `a71a878ddfcca1cf44c303c92e0c5418174e1388` |
| Tuple fallback message | [#1011](https://github.com/leits/MeetingBar/pull/1011) | `b1efd3e692ebb2aad5124397c500e58d876792db` |

The integration includes master `fdd799b60ad8bb307b592f368ee5c318c3fc9da3` after the Tuple merge. Rejected PR #1003 is excluded.

## Contributor history

The focused adaptations now retain the original commits as ancestors, with their exact SHAs, author identities and dates. The history-only merges retain the already reviewed adaptations; subsequent master merges resolve the shared changelog and localization additions.

| Original PR | Adaptation | Preserved contribution |
| --- | --- | --- |
| #982 | #1004 | Both Trevor Sayre commits |
| #972 | #1005 | Both Jeremy Friedel commits |
| #979 | #1006 | Anand Hegde's original commit |
| #970 | #1008 | All 14 Weblate commits, including the five translation contributors |
| #1001 | master / #1011 | Existing Tuple commits remain intact through the master merge |

Use merge commits for the focused PRs to preserve these original SHAs; squash/rebase would replace them. This candidate also retains all updated focused heads as parents.

## Draft RC3 release notes

This release candidate includes the current v5 reliability fixes and the following final additions:

- Fix clipped two-line menu bar titles while preserving native button interaction.
- Recognize complete Clari Copilot Google Meet wrapper paths and apply the selected Google account; reject partial-code/path suffixes.
- Offer an optional Tuple app opener with fallback to the selected browser and no misleading browser error when Tuple is unavailable.
- Run configured event-start AppleScripts for eligible events without meeting URLs. The existing handler receives `EMPTY` for the URL and service. The Preferences test button supports these events and the help distinguishes event-start and join hooks.
- Let users hide “now” in ongoing-event times; the default appearance is unchanged.
- Refresh Czech, Dutch, Japanese and Simplified Chinese translations.

RC3 also includes the SafeLinks and personal Gmail alias fixes already merged after RC2. See CHANGELOG.md for the complete v5 changes.

## Release gates

- [ ] Focused PRs reviewed and merged; refresh integration on the resulting master and review its final diff.
- [ ] Combined macOS CI: logic tests, app-hosted tests, localization validation, SwiftLint and required repository checks pass on the final commit.
- [ ] Stacked layout: active and inactive displays, Retina scaling, long and missing titles, normal/underlined/inactive styles, switching inline/stacked/hidden time.
- [ ] Native status button: left/right/modifier clicks and VoiceOver expose the full event title and time.
- [ ] Clari: a real invite opens the correct Meet meeting with the selected account; wrapped SafeLinks retain expected behavior.
- [ ] Tuple installed: the optional Tuple App mode joins the call once. Tuple absent: the original HTTPS URL opens once in the selected browser. Browser mode never launches Tuple.
- [ ] Event-start script: linked and no-link events fire once with the existing named handler; no-link URL/service are `EMPTY`. Dismissed/declined/canceled and filtered events do not fire. Repeat reconcile and lock/unlock do not duplicate a successful run.
- [ ] Hide now: changing the preference redraws immediately in inline and stacked layouts; upcoming times and the default remain unchanged.
- [ ] Upgrade from 4.11.6 and RC2 preserves calendars, provider selection, browser preferences, script configuration and dismissal state; new settings retain defaults.
- [ ] Clean first launch for EventKit and Google, provider switch/sign-out, wake refresh, notifications, login item, and termination while work is active.
- [ ] Signed Release build/archive succeeds with the intended team and distribution profile; verify hardened runtime, sandbox, OAuth callback, login item and StoreKit configuration as described in docs/ARCHITECTURE.md.
- [ ] Verify the signed artifact reports 5.0.0 (172), and complete distribution-specific notarization/App Store validation.
- [ ] Update release date/notes to the actual final scope, create the new RC3 tag from the validated commit, and publish as a prerelease only.

Run `make lint`, `make validate-strings`, `make test`, and `make build-release` on the signing-capable Mac. Debug CI cannot establish signing, real app opening, display interaction or upgrade behavior.
