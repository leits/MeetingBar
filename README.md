
[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner-direct-single.svg)](https://stand-with-ukraine.pp.ua)

[![GitHub license](https://img.shields.io/github/license/leits/MeetingBar.svg)](https://github.com/leits/MeetingBar/blob/master/LICENSE)
[![Translation state](https://hosted.weblate.org/widgets/meetingbar/-/app/svg-badge.svg)](https://hosted.weblate.org/engage/meetingbar/)
[![Github all releases](https://img.shields.io/github/downloads/leits/MeetingBar/total.svg)](https://GitHub.com/leits/MeetingBar/releases/)
[![Made in Ukraine](https://img.shields.io/badge/made_in-ukraine-ffd700.svg?labelColor=0057b7)](https://stand-with-ukraine.pp.ua)

**MeetingBar** is a menu bar app for your calendar meetings (macOS 10.15+).

Integrated with 20+ meeting services so you can quickly join meetings from event or create ad hoc meeting.

<img src="https://github.com/leits/MeetingBar/blob/master/screenshot.png" width="700">

<a href="https://www.producthunt.com/posts/meetingbar?utm_source=badge-featured&utm_medium=badge&utm_souce=badge-meetingbar" target="_blank"><img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=203807&theme=light" alt="MeetingBar - Join your next meeting from your menu bar | Product Hunt Embed" style="width: 250px; height: 54px;" width="250px" height="54px" /></a>
[![Download on the Mac App Store](mas_badge.png)](https://apps.apple.com/us/app/id1532419400)

## Features

* Show the next meeting in the system statusbar
  * Show upcoming meeting with name or hidden
  * Shorten title to save space in the statusbar
  * Choose icon to show for the upcoming meeting, e.g. the app icon or the meeting type icon
  * Show only meetings within a certain timeframe (e.g. show only meetings in the next 30 minutes)
* Show all upcoming events from today and tomorrow (optional) in the expanded system menubar
  * show or hide all day events or only all day events with a meeting link
  * show or hide events without guests
  * show or hide declined events
  * show or hide meeting type icons
  * show or hide pending events
* Show events from all your macos calendars incl. notes, location and attendees
* Open the event in macos calendar or Fantastical 3 (if the app is installed)
* Join the next onlinemeeting with a single shortcut
* Select for specific services like zoom or ms teams to start the meeting in the installed app or browser
* Attend an online meeting using one click
* Create a new meeting in your favorite app by using a shortcut
* Configure your favorite browser to use for joining meetings and new meetings
* Sends macos notifications for upcoming events
* Bookmark your favorite meeting, show it in the statusmenu and make it accessible with a shortcut
* Automatic launch the app when your system starts
* Execute your custom apple script, e.g. to pause music when joining a new online event

## Setup

1. Install:

* From the [App Store](https://apps.apple.com/us/app/id1532419400)
* From homebrew `brew install meetingbar`
* Manual download the [latest version](https://github.com/leits/MeetingBar/releases/latest/download/MeetingBar.dmg)

2. Make sure your calendar is synchronized to macOS calendar or [add a calendar account](https://support.apple.com/guide/calendar/add-or-delete-calendar-accounts-icl4308d6701/mac).
3. Open the app and go through the onboarding.
4. Never miss your next meeting again :tada:

If you have some installation problems or some other questions please check the [FAQ](../../wiki/FAQ) or [add an issue](https://github.com/leits/MeetingBar/issues/new).

## Supported meeting services

Check the full list [here](https://github.com/leits/MeetingBar/discussions/108).

## Third-Party Integrations

* [Raycast commands](https://github.com/raycast/script-commands/tree/master/commands#meetingbar)

## Other similar apps

* NextMeeting - free, more simple
* Meeter - commercial solution, provides similar features and more regarding contacts

## Contribute

Read more [here](CONTRIBUTING.md) about how to contribute to MeetingBar.

## Support the project

❤️ Love this project?

Support on [Patreon](https://www.patreon.com/meetingbar) or via in-app purchases.

## Credits

MeetingBar is **stable** and in **active development** by [leits](https://github.com/leits). Written in Swift 5.0.

MeetingBar also uses these resources:

* [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for managing global keyboard shortcuts
* [Defaults](https://github.com/sindresorhus/Defaults) for managing user settings
* [SwiftyStoreKit](https://github.com/bizz84/SwiftyStoreKit) for patronage via in-app purchases

App logo made by [Miroslav Rajkovic](https://www.rajkovic.co/).

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

If you encounter any bugs or have a feature request, [add an issue](https://github.com/leits/MeetingBar/issues/new).
