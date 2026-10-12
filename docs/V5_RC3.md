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
| Stacked status title | [#1004](https://github.com/leits/MeetingBar/pull/1004) | `fe4361c700d54785795bcac3adc0e3c784951f68` |
| Clari | [#1005](https://github.com/leits/MeetingBar/pull/1005) | `abc7eaaf42daefc7e5575416ae2bcbb7978baa69` |
| Tuple | [#1001](https://github.com/leits/MeetingBar/pull/1001) | `308e33dcbead276c1ed1975f85f8009d484aeed8` |
| Hide now | [#1006](https://github.com/leits/MeetingBar/pull/1006) | `9b6607d5ca886727315d2f750a7ea2a3fb6ccdee` |
| Event-start scripts | [#1007](https://github.com/leits/MeetingBar/pull/1007) | `565a78cf5c89d435bf0d0c59831a60cfe48fe5ec` |
| Translations | [#1008](https://github.com/leits/MeetingBar/pull/1008) | `980f61036a17a3805a08f9ae8dd53416cc660197` |

The integration is based on master `c6b3b6fedb69dd049cadcbbf60349c1c96838be6`. Rejected PR #1003 is excluded.

## Draft RC3 release notes

This release candidate includes the current v5 reliability fixes and the following final additions:

- Fix clipped two-line menu bar titles while preserving native button interaction.
- Recognize Clari Copilot Google Meet wrappers and apply the selected Google account.
- Offer an optional Tuple app opener with fallback to the selected browser.
- Run configured event-start AppleScripts for eligible events without meeting URLs. The existing handler receives `EMPTY` for the URL and service.
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
