# MeetingBar Dependency And Release Checklist

This is the release-sensitive companion to [`ARCHITECTURE.md`](ARCHITECTURE.md). The release owner is responsible for keeping the project file, resolved dependencies, capabilities, Google configuration, StoreKit products, and shipped build aligned.

## Dependency policy

Direct dependencies are declared in `MeetingBar.xcodeproj/project.pbxproj` and pinned by `MeetingBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

| Package | Project requirement | Current resolved version | Purpose |
|---|---|---|---|
| KeyboardShortcuts | `2.3.0 ..< 2.4.0` | `2.3.0` | Global shortcuts |
| Defaults | `9.0.2 ..< 9.1.0` | `9.0.3` | Typed user defaults |
| LaunchAtLogin | `5.0.2 ..< 6.0.0` | `5.0.2` | Login item integration |
| AppAuth-iOS | `2.0.0 ..< 3.0.0` | `2.0.0` | Google OAuth |

`swift-syntax 601.0.1` is currently transitive. StoreKit 2 is a system framework and has no package entry. SwiftyStoreKit is no longer part of the project.

When updating a dependency:

1. Read its release notes and minimum macOS/Swift requirements.
2. Change the Xcode package requirement intentionally; do not edit only `Package.resolved`.
3. Review the resolved diff for unexpected transitive updates.
4. Run the full validation commands below.
5. Name dependency, project-file, entitlement, or capability changes in the PR and release notes when user-visible.

## Release-sensitive configuration

Current app settings are defined in the Xcode project:

- Bundle identifier: `leits.MeetingBar`
- Minimum macOS: `12.0`
- Swift language mode: `6.0`
- Marketing version and build number: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
- Hardened runtime: enabled
- Entitlements file: `MeetingBar/MeetingBar.entitlements`

`XCConfig/Project.xcconfig` supplies the development team, strict concurrency setting, and Google values. `XCConfig/DevTeamOverride.xcconfig` is an optional git-ignored local team override.

Before creating a signed build:

- Increment `MARKETING_VERSION` and/or `CURRENT_PROJECT_VERSION` as appropriate.
- Confirm Release uses the intended signing team, certificate, and provisioning profile.
- Build the Release configuration and inspect the final archive, not only an unsigned Debug build.

## Google OAuth

The shipped configuration must provide:

- `GOOGLE_CLIENT_NUMBER`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_AUTH_KEYCHAIN_NAME`

`MeetingBar/Info.plist` exposes those values to `GCEventStore`. Its callback scheme is:

```text
com.googleusercontent.apps.$(GOOGLE_CLIENT_NUMBER)
```

The same client number must produce the redirect URI used by the app:

```text
com.googleusercontent.apps.<client-number>:/oauthredirect
```

Verify sign-in, callback routing, token restoration after relaunch, sign-out, and provider switching. Never release with the `REPLACE_BY_YOUR_...` placeholders.

## Capabilities And Sandbox

The app currently ships with:

- App Sandbox
- Calendar access
- Outbound network access
- User-selected read/write file access for scripts and selected applications
- Time-sensitive user notifications
- Hardened runtime

Any change to `MeetingBar/MeetingBar.entitlements`, `MeetingBar/Info.plist`, URL schemes, sandbox access, or script execution needs both a signed-build check and a clean-user manual check. Unsigned local builds may warn that entitlements cannot be applied; that warning does not validate the signed artifact.

## App Store And Direct Builds

`AppSourceDetector` treats a build as App Store-installed when `Bundle.main.appStoreReceiptURL` exists on disk. Menu behavior and diagnostics use this value.

For an App Store or StoreKit sandbox build:

- Confirm the receipt is present and the app is classified as App Store-installed.
- Verify StoreKit 2 loads all patronage products:
  - `leits.MeetingBar.patronage.3Month`
  - `leits.MeetingBar.patronage.6Month`
  - `leits.MeetingBar.patronage.12Month`
- Test purchase cancellation, a verified purchase, restore/sync, entitlement replay after relaunch, and transaction-update handling.
- Confirm transaction identifiers are not processed twice.

For a direct build:

- Confirm missing App Store receipt classifies the app as direct.
- Confirm App Store-only menu actions are hidden.
- Verify calendar access, Google OAuth, launch at login, notifications, and user-selected script bookmarks under the shipped signature.

## Validation

Run before release:

```bash
make lint
make validate-strings
make test
make build-release
```

Then manually verify:

- First launch and onboarding for EventKit and Google Calendar
- Cancel Google authorization during onboarding and provider switching; confirm the previous provider and selected calendars remain active
- Select a shared or public Google calendar alongside another calendar, then refresh and relaunch; confirm both selections and their events remain available
- Restore an existing Google session and refresh an expired access token without requiring authorization again
- Successful provider switching and Google sign-out
- Wake, screen lock/unlock, timezone change, and day change refreshes
- Status bar title/menu with no events, next event, long titles, and back-to-back events
- Join, alternate links, dismiss, snooze, fullscreen, auto-join, and event-start scripts
- Existing joinable meeting shows a fullscreen notification and still joins correctly
- No-link event does not show a fullscreen notification by default
- Enable fullscreen notifications for events without meeting links; confirm a no-link event shows one
- No-link fullscreen notification shows Dismiss only, with no Join or Open in Calendar action
- No-link fullscreen notification does not open a meeting or run a join script
- Esc dismisses the fullscreen notification
- The Dismiss button dismisses the fullscreen notification
- On a multi-monitor setup, fullscreen notification appears on the active/focused screen
- Proton Meet link is detected and opens unchanged in the browser
- Workplace call opens in the default browser mode
- Workplace App mode opens Workchat and falls back to the original browser URL when unavailable
- Zoom opens correctly in default browser, Zoom App, and Zoom Web App modes
- Zoom `/my/` personal room opens once and does not attempt a second native/web-app launch
- Google Meet opens correctly in default browser and MeetInOne modes
- Google Meet PWA mode launches the installed Chrome PWA when available
- Google Meet PWA mode falls back to the configured browser when Chrome or the PWA is unavailable
- Notification authorization denied and granted paths
- Preferences, changelog, diagnostics copy, launch at login, and app URL routes
- App termination while refresh, OAuth, delayed actions, or StoreKit updates are active

Record the tested macOS version, build number, distribution path (App Store sandbox or direct signed build), and any skipped checks in the release notes.
