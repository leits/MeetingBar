[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner-direct-single.svg)](https://stand-with-ukraine.pp.ua)

[![GitHub license](https://img.shields.io/github/license/leits/MeetingBar.svg)](https://github.com/leits/MeetingBar/blob/master/LICENSE)
[![Translation state](https://hosted.weblate.org/widgets/meetingbar/-/app/svg-badge.svg)](https://hosted.weblate.org/engage/meetingbar/)
[![Github all releases](https://img.shields.io/github/downloads/leits/MeetingBar/total.svg)](https://github.com/leits/MeetingBar/releases/)
[![Made in Ukraine](https://img.shields.io/badge/made_in-ukraine-ffd700.svg?labelColor=0057b7)](https://stand-with-ukraine.pp.ua)

**MeetingBar** is a lightweight macOS menu-bar app that shows your current or next calendar meeting and lets you join it in one click.

It keeps meetings visible in the status bar, detects meeting links from calendar events, supports macOS Calendar and Google Calendar, and works with 50+ meeting services including Google Meet, Zoom, Microsoft Teams, Webex, and Discord.

MeetingBar is free, open source, and privacy-respecting.

<img src="https://github.com/leits/MeetingBar/blob/master/screenshot.png" width="700">

<a href="https://www.producthunt.com/posts/meetingbar?utm_source=badge-featured&utm_medium=badge&utm_souce=badge-meetingbar" target="_blank"><img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=203807&theme=light" alt="MeetingBar - Join your next meeting from your menu bar | Product Hunt Embed" style="width: 250px; height: 54px;" width="250px" height="54px" /></a>

[![Download on the Mac App Store](mas_badge.png)](https://apps.apple.com/us/app/id1532419400)

<a href="https://www.buymeacoffee.com/meetingbar" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## Install

MeetingBar requires **macOS 12.0 or later**.

### Mac App Store

Download MeetingBar from the [Mac App Store](https://apps.apple.com/us/app/id1532419400).

### Homebrew

```bash
brew install --cask meetingbar
```

### Manual download

Download the latest DMG from the [releases page](https://github.com/leits/MeetingBar/releases/latest/download/MeetingBar.dmg).

## Calendar providers

MeetingBar works with:

* **macOS Calendar**: use any calendar account synchronized with Calendar.app, including iCloud, Google, Exchange, Office 365, Yahoo, AOL, and others.
* **Google Calendar**: connect Google Calendar directly from MeetingBar.

After installation, open MeetingBar and go through onboarding to choose your calendar source and preferences.

## Features

### See what is next

* Show the current or next meeting in the macOS status bar.
* Display meeting title, time, countdown, icon, or meeting service.
* Show upcoming events from today and tomorrow in the menu.
* Filter all-day, declined, tentative, pending, or linkless events.
* Shorten long meeting titles to keep the menu bar readable.

### Join meetings faster

* Join the current or next online meeting with one click.
* Join the nearest meeting with a global keyboard shortcut.
* Create ad-hoc meetings from your preferred meeting service.
* Open meeting links in a preferred browser or native app per service.
* Open event details in macOS Calendar or Fantastical.

### Get meeting reminders

* Receive macOS notifications before meetings.
* Use full-screen reminders for important meeting starts.
* Dismiss meeting notifications when you no longer need them.
* Configure reminders around your own workflow.

### Customize and automate

* Bookmark recurring meetings and access them quickly.
* Launch MeetingBar automatically at login.
* Use Shortcuts and AppleScript integrations.
* Run custom AppleScript, for example to pause music when joining a meeting.

## Supported meeting services

MeetingBar supports more than 50 meeting services, including:

Google Meet, Zoom, Microsoft Teams, Webex, GoToMeeting, Skype, Discord, Jitsi, RingCentral, BlueJeans, Whereby, Slack Huddle, FaceTime, LiveKit Meet, Meetecho, StreamYard, and many others.

See the [full supported services list](https://github.com/leits/MeetingBar/discussions/108).

## Privacy

MeetingBar does not collect personal data.

Calendar data is used by the app to show your meetings, detect meeting links, and open the correct meeting action.

## Troubleshooting

If meetings do not appear, links are not detected, or Google Calendar needs reconnecting, check the [FAQ](../../wiki/FAQ), install the [latest release](https://github.com/leits/MeetingBar/releases/latest), or [open an issue](https://github.com/leits/MeetingBar/issues/new).

Useful details for bug reports:

* MeetingBar version
* macOS version
* Calendar provider: macOS Calendar or Google Calendar
* Meeting service: Zoom, Google Meet, Microsoft Teams, Webex, etc.
* Whether the event is recurring or one-off
* Whether the event is accepted, tentative, pending, declined, or canceled
* Sanitized event title, description, location, and URL fields
* Whether manual refresh changes the behavior
* Screenshots or logs when available

## Third-party integrations

* [Raycast commands](https://github.com/raycast/script-commands/tree/master/commands#meetingbar)

## Contributing

MeetingBar is open source and welcomes focused fixes, meeting service integrations, translations, reliability improvements, and documentation updates.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Support the project

MeetingBar is free and community-supported.

You can support development through [Patreon](https://www.patreon.com/meetingbar), in-app purchases, or [Buy Me a Coffee](https://www.buymeacoffee.com/meetingbar).

## Credits

MeetingBar is stable and in active development by [leits](https://github.com/leits). Written in Swift 6.

MeetingBar also uses these resources:

* [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for managing global keyboard shortcuts
* [Defaults](https://github.com/sindresorhus/Defaults) for managing user settings
* StoreKit for patronage via in-app purchases

App logo made by [Miroslav Rajkovic](https://www.rajkovic.co/).

## Contributors ✨

Thanks goes to these wonderful people:

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->

<!-- prettier-ignore-start -->

<!-- markdownlint-disable -->

<table>
  <tr>
    <td align="center"><a href="https://github.com/leits"><img src="https://avatars.githubusercontent.com/u/12017826?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Andrii Leitsius</b></sub></a><br /><a href="https://github.com/leits/MeetingBar/commits?author=leits" title="Code">💻</a> <a href="#maintenance-leits" title="Maintenance">🚧</a></td>
    <td align="center"><a href="https://github.com/jgoldhammer"><img src="https://avatars.githubusercontent.com/u/3872101?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Jens Goldhammer</b></sub></a><br /><a href="https://github.com/leits/MeetingBar/commits?author=jgoldhammer" title="Code">💻</a> <a href="#maintenance-jgoldhammer" title="Maintenance">🚧</a></td>
    <td align="center"><a href="https://github.com/0bmxa"><img src="https://avatars.githubusercontent.com/u/15385891?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Max</b></sub></a><br /><a href="https://github.com/leits/MeetingBar/commits?author=0bmxa" title="Code">💻</a></td>
  </tr>
</table>

<!-- markdownlint-restore -->

<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

If you encounter any bugs or have a feature request, [open an issue](https://github.com/leits/MeetingBar/issues/new).
