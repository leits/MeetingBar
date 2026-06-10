# Тимчасовий план архітектурної міграції MeetingBar

> Робочий документ. Ціль - довести MeetingBar до простої, зрозумілої та завершеної архітектури без legacy-хвостів. Це не план "ідеальної Clean Architecture"; це план для open-source macOS app, який має бути легко підтримувати основному мейнтейнеру без глибокого Swift/AppKit досвіду.

## Принцип

Архітектура - це не папки. Архітектура - це відповідь на питання:

- куди приходить дія користувача або системи;
- хто тримає стан;
- хто приймає рішення;
- хто виконує macOS/API side effects;
- де це тестується.

Фінальне правило:

```text
UI sends actions.
AppModel coordinates.
Feature components do workflows.
Policies decide.
macOS integrations execute.
```

Не використовуємо як основну мову плану терміни `UseCase`, `Client`, `Port`, `Interactor`, `Repository`. Назви мають звучати як частини MeetingBar:

- `EventManager`
- `EventStore`
- `MeetingOpener`
- `NotificationScheduler`
- `SnoozeService`
- `AppSettings`
- `OnboardingHandler`
- `OnboardingRouter`
- `StatusBarItemController`
- `WindowCoordinator`
- `PatronageService`
- `AppClock`
- `URLHandler` / `AppRouteHandler`
- `PermissionReporter`
- `AppMessageCenter`

## Рішення після expanded review

Це вже не мінімальна міграція. Це один великий architecture/codebase redesign, який можна доставити малими PR. Тому план включає не тільки ownership потоків, а й модернізацію залежностей, concurrency, logging і найбільші hotspots коду.

Що змінюємо порівняно з попередньою версією плану:

- не робимо rename `EventManager -> CalendarSync` самоціллю. Фінальна ціль - slim `EventManager`, який займається тільки calendar/event orchestration;
- не робимо rename `EventStore -> CalendarProvider`. `EventStore` вже нормальна назва для provider boundary;
- не вводимо blanket `DefaultsSettings`, якщо `AppSettings.current` вже є нормальним read boundary. Додаємо контрольовані `AppSettings` write helpers і `AppModel` actions для runtime-affecting writes;
- не створюємо `PreferencesModel` для кожної tab. SwiftUI `@Default` bindings можуть лишитись для простих persisted UI settings;
- не замінюємо існуючі `OnboardingHandler`, `OnboardingRouter`, `OnboardingStep` на новий шар. Вузька ціль - onboarding має йти через `AppModel` і не створювати другий `EventManager`;
- не перейменовуємо `DiagnosticsContext` у `DiagnosticsBuilder`, якщо існуюча назва лишається зрозумілою;
- додаємо реальні codebase hotspots: `MenuBuilder.makeEventItem` decomposition, `SnoozeService`, StoreKit 2, structured logging, strict concurrency, task ownership audit, AppIntent через `AppModel`;
- додаємо cross-cutting redesign tracks: time/clock boundary, URL/OAuth routing, permissions/capabilities, user-facing message ownership, SwiftPM logic boundary, dependency/release policy.

## Фінальна модель

```text
AppDelegate
  creates and wires objects
  owns OS lifecycle callbacks
  does not contain business rules

AppModel
  owns AppState
  receives AppAction
  coordinates feature components

Feature components
  AppSettings
  EventManager
  EventStore implementations
  MeetingOpener
  NotificationScheduler
  SnoozeService
  OnboardingHandler / OnboardingRouter
  WindowCoordinator
  PatronageService
  DiagnosticsContext
  MeetingBarLogger
  AppClock
  URLHandler / AppRouteHandler
  PermissionReporter
  AppMessageCenter

UI controllers / views
  StatusBarItemController
  PreferencesView
  OnboardingView
  NotificationCenterDelegate
  AppIntents

Pure policies
  EventFiltering
  EventSelection
  StatusBarPresenter
  MenuPresentation
  NotificationPlanner
  SnoozePlanner
  MeetingLinkDetector
  MeetingOpeningPolicy
  Menu event-item helpers
  URL route parsing
  User message mapping
```

## Що має бути очевидно після міграції

Новий contributor має швидко знайти:

- refresh календарів: `AppModel -> EventManager`;
- provider switch: `AppModel -> EventManager`;
- join meeting: `AppModel -> MeetingOpener`;
- notification planning: `AppModel -> NotificationScheduler`;
- snooze: `AppModel/NotificationCenterDelegate -> SnoozeService`;
- notification response: `NotificationCenterDelegate -> AppModel`;
- settings reads: `AppSettings.current`;
- runtime-affecting settings writes: `AppSettings` write helpers + `AppModel`;
- simple Preferences persistence: SwiftUI `@Default` bindings where they do not trigger runtime workflow;
- Onboarding behavior: `OnboardingHandler/OnboardingRouter -> AppModel/EventManager/AppSettings`;
- status bar rendering: `StatusBarItemController + MenuBuilder + StatusBarPresenter`;
- event menu item rendering: decomposed helpers inside/near `MenuBuilder`;
- windows: `WindowCoordinator`;
- AppIntent actions: `AppIntent -> AppModel`;
- App Store / patronage: `PatronageService` with StoreKit 2;
- diagnostics: `DiagnosticsContext`;
- scripts: `MeetingOpener` for join scripts, `NotificationScheduler` for event-start scripts.
- logging: `MeetingBarLogger` / `os.Logger` categories.
- time/date decisions: `AppClock` or injected `now`;
- URL/OAuth routing: `URLHandler` / `AppRouteHandler`;
- permissions/capabilities: `PermissionReporter`;
- user-facing errors/messages: `AppMessageCenter`;
- pure logic placement: `MeetingBarLogic` SwiftPM target;
- dependency/release ownership: dependency policy + release checklist.

## Коротка карта виконання

Це швидкий робочий індекс. Детальний scope кожного PR описаний нижче.

| Phase | PR | Ціль | Основні owner-и | Exit signal |
| --- | --- | --- | --- | --- |
| Foundation | 0 | Safety baseline | existing bug sites | known correctness bugs fixed before architecture work |
| Foundation | 1 | Warning-free Swift 6 | concurrency warning sites | Xcode Debug build has no Swift concurrency warnings |
| Foundation | 2 | Strict concurrency, CI, testing harness, SwiftPM boundary | build settings, workflows, test fakes, `MeetingBarLogic` | strict checks visible and new PRs can add focused tests |
| Behavior | 3 | AppAction route extension + AppClock | `AppModel`, `AppAction`, `AppClock` | important actions are traceable and time-sensitive logic is testable |
| Behavior | 4 | AppSettings write helpers | `AppSettings`, `AppModel` | runtime settings writes stop coming from random feature files |
| Behavior | 5 | External entry points + StatusBar decoupling | `AppIntent`, `URLHandler`, `StatusBarItemController` | no delegate casts for intents/status-bar/URL actions |
| Behavior | 6 | Window ownership | `WindowCoordinator` | `AppDelegate` delegates window create/focus/close work |
| Behavior | 7 | Onboarding through AppModel + permissions | existing onboarding types, `PermissionReporter` | no double `EventManager` initialization and permission state is explicit |
| Domain | 8 | Data-only `MBEvent` | `MBEvent`, mappers/policies | domain models have no AppKit/Defaults side effects |
| Domain | 9 | Meeting opening + scripts | `MeetingOpener`, script runner | join/email/open/script side effects have one owner path |
| Domain | 10 | Notifications + snooze | `NotificationScheduler`, `SnoozeService`, `AppModel` | notification and snooze actions route through app model |
| Domain | 11 | MenuBuilder hotspot | `MenuBuilder` helpers | `makeEventItem` is decomposed behind existing tests |
| Modernization | 12 | StoreKit 2 patronage | `PatronageService` | SwiftyStoreKit removed and sandbox flow verified |
| Modernization | 13 | Logging, messages, task audit, release policy | `MeetingBarLogger`, `AppMessageCenter`, task owners, docs | `NSLog` replaced, messages owned, tasks cancellable, release checklist updated |
| Final | 14 | Final cleanup | `AppDelegate`, `EventManager`, docs, final searches | no legacy runtime path remains |

## Критерії завершення

Міграція завершена тільки коли:

- `AppDelegate` є composition root, а не місцем бізнес-логіки.
- `AppModel` є єдиним маршрутом для важливих дій: refresh, provider switch, join, dismiss, notification response, shortcuts, onboarding completion.
- `StatusBarItemController` не знає про `AppDelegate` і не читає app state напряму через delegate.
- `AppIntent` не кастить `NSApplication.shared.delegate as? AppDelegate`; intents читають state і надсилають actions через `AppModel` route.
- Preferences не мутують важливий app flow напряму через `Defaults`. Runtime-affecting prefs ідуть через `AppModel`/`AppSettings` write helpers.
- SwiftUI `@Default` bindings лишаються тільки для простих persisted UI settings, які не запускають provider switch, refresh, notification reconcile або meeting behavior.
- Onboarding не створює власний flow паралельно до normal app flow.
- Onboarding не створює другий `EventManager` після completion.
- `MBEvent` є data-only моделлю, без `openMeeting()` і `emailAttendees()`.
- `Defaults[...]` для reads ізольований у `AppSettings.current` або documented UI-only exceptions; runtime writes ідуть через `AppSettings` helpers / `AppModel`.
- `NSApplication.shared.delegate as? AppDelegate` не використовується у feature-коді.
- Calendar providers закриті за `EventStore`.
- `EventManager` slim: refresh, provider switch, provider health, coalescing. Він не відкриває meetings, не будує menu, не планує notifications і не володіє Preferences/Onboarding flow.
- Meeting opening виконується тільки через `MeetingOpener`.
- AppleScript join side effects виконуються через `MeetingOpener`/script runner, а scheduled event-start scripts через notification/action runner.
- Notification responses не відкривають meeting напряму.
- Snooze має одного owner-а: `SnoozeService`/pure snooze planner + notification scheduling adapter.
- `MenuBuilder.makeEventItem` розбитий на зрозумілі helper-и з покриттям існуючими tests.
- Window creation/focus/close behavior не розмазаний по `AppDelegate`.
- App Store / patronage flow використовує StoreKit 2 через `PatronageService`, без `SwiftyStoreKit`.
- `PatronageService` не стає state machine без потреби; це wrapper над StoreKit 2 + persistence/reporting hooks.
- Diagnostics читають фінальний `AppState`/`AppSettings`/provider health snapshots через `DiagnosticsContext`, а не тримають legacy references живими.
- `I18N.instance` або прибраний, або записаний як deliberate singleton exception.
- Long-running tasks мають явного owner-а і cancel path на terminate/provider switch.
- Structured logging використовує `os.Logger`, а не scattered `NSLog`.
- Time-sensitive workflow code не викликає `Date()` / `Calendar.current` напряму без `AppClock` або injected `now`.
- URL/OAuth callbacks мають один route owner і не викликають `AppDelegate`/provider internals напряму з parsing code.
- Permission/capability state для Calendar, notifications, Google OAuth, scripts і sandbox assumptions доступний через явний reporter/snapshot.
- User-facing errors/messages проходять через `AppMessageCenter` або documented UI adapter, а не через random `sendNotification` / alert calls.
- Pure policies/parsing/planning/formatting живуть у `MeetingBarLogic` SwiftPM target, якщо їм не потрібні AppKit/EventKit/UserNotifications/Defaults/StoreKit.
- Dependency updates і release-sensitive project settings мають documented owner/checklist: SPM packages, entitlements, Info.plist URL scheme, sandbox, App Store/direct build differences.
- Xcode Debug build проходить без Swift concurrency warnings.
- strict concurrency checking увімкнений/перевірений для SwiftPM і Xcode build settings, а known framework interop exceptions задокументовані.
- CI запускається на Swift, project, workflow, config, script і base localization зміни.

## Final Allowed Exceptions

Фінальні винятки мають бути короткими, явними і перевіреними final searches. Якщо виняток не записаний тут або в постійній архітектурній документації, це не виняток.

- `Defaults[...]` дозволений тільки в `AppSettings.current`, `AppSettings` write helpers, settings migration code, tests/fixtures, або в дуже малих UI-only SwiftUI `@Default` bindings, які не змінюють runtime flow. Кожен UI-only виняток має бути названий у фінальній документації.
- `NSApplication.shared.delegate as? AppDelegate` не дозволений у feature-коді. AppKit entry points мають отримувати closures/dependencies від composition root.
- `NSUserAppleScriptTask` дозволений тільки в одному script execution owner-и для join flow і одному owner-и для scheduled event-start flow. UI files не виконують scripts.
- `nonisolated(unsafe)`, `@unchecked Sendable` і `swiftlint:disable` дозволені тільки з коротким коментарем, чому це framework interop або tooling limitation, а не спосіб обійти дизайн.
- `I18N.instance` може лишитись тільки як documented UI/infrastructure singleton. Він не може бути каналом для app workflow state.
- `EventManager` може лишитись фінально, але тільки як slim calendar/event orchestration owner. Якщо він знову починає володіти meeting opening, menu rendering, notification responses або settings writes, це regression.
- `Date()` / `Calendar.current` дозволені напряму в leaf UI formatting або one-off app shell code. Core workflow, scheduling, selection, filtering і tests мають використовувати `AppClock`/injected `now`.
- `try!`, `as!`, force-unwrapped Bundle config і regex constants дозволені тільки якщо startup/config validation або static invariant documented. Інакше вони мають стати throwing/failable path з user-facing message.

## Runtime Flows

### Refresh

```text
timer / wake / manual refresh / relevant settings change
  -> AppModel.send(.refreshRequested)
  -> EventManager refreshes using AppSettings snapshot
  -> active EventStore fetches calendars/events
  -> EventFiltering / EventSelection apply rules
  -> AppModel updates AppState
  -> StatusBarItemController renders new state
  -> NotificationScheduler.reconcile(...)
```

### Join Meeting

```text
status bar / shortcut / notification / fullscreen / AppIntent
  -> AppModel.send(.joinMeeting(eventID))
  -> AppModel finds event in AppState
  -> MeetingOpener.open(event)
  -> MeetingOpeningPolicy decides
  -> NSWorkspace / AppleScript / notification side effect executes
```

### Provider Switch

```text
Preferences provider picker / Onboarding provider selection
  -> AppModel.send(.providerChanged(provider, signOut))
  -> AppSettings write helper stores provider and clears selected calendars when needed
  -> EventManager switches EventStore
  -> signIn if needed
  -> refresh
  -> AppState updates calendars/events/providerHealth
```

### Notification Response

```text
UNUserNotificationCenterDelegate
  -> NotificationResponseAction
  -> AppModel.send(.notificationResponse(...))
  -> AppModel routes join/dismiss/snooze
```

### Preferences Change

```text
Preferences UI change
  -> simple UI-only setting may use @Default directly
  -> runtime-affecting setting sends AppAction / AppSettings write helper
  -> AppModel coordinates refresh/render/reconcile
```

Not every preference toggle needs a full `AppAction`. Simple persisted appearance values can keep SwiftUI `@Default` bindings. But settings that trigger calendar refresh, provider switch, notification reconcile, or meeting behavior must go through `AppModel`.

### Onboarding Completion

```text
OnboardingView
  -> OnboardingHandler / OnboardingRouter selected provider
  -> AppModel.send(.onboardingCompleted(provider))
  -> AppSettings write helper marks onboarding completed
  -> AppModel performs normal provider switch / refresh flow
  -> main status bar flow starts
```

Onboarding must not create a second private initialization path. It should reuse the same provider switch and refresh flow as Preferences.

### Window Opening

```text
status bar / URL callback / onboarding / notification action
  -> AppModel or AppDelegate asks WindowCoordinator
  -> WindowCoordinator opens/focuses/closes the right window
```

Windows are UI shell, not business logic. `WindowCoordinator` can stay in the app target and use AppKit directly.

### App Store / Patronage

```text
App launch / restore / purchase
  -> PatronageService talks to StoreKit 2
  -> AppSettings write helper stores patronage/app-source state
  -> AppModel or notification helper reports user-visible outcome
```

Patronage code should not become a second settings system.

### Diagnostics

```text
Preferences Status tab
  -> DiagnosticsContext builds report from AppState, AppSettings, ProviderHealth, app/system metadata
  -> UI copies or displays report
```

Diagnostics must follow the new state ownership. They should not keep old references alive just because they are convenient.

### AppIntent

```text
Shortcuts / AppIntent
  -> AppModelAccessor or injected app action sink
  -> AppModel.send(.joinMeeting / .dismissMeeting / read nearest event details)
  -> same meeting/status flow as status bar
```

AppIntent must not call `StatusBarItemController` or `AppDelegate` directly.

### Snooze

```text
notification response
  -> NotificationCenterDelegate converts response to action
  -> AppModel.send(.snoozeMeeting(eventID, action))
  -> SnoozeService computes request timing/content
  -> notification scheduling adapter schedules request
```

Snooze timing is pure and tested. UserNotifications calls are adapter code.

### Time / Clock

```text
timer / selection / scheduling / rendering decision
  -> owner receives AppClock or injected now
  -> pure policy uses explicit Date input
  -> tests fix time deterministically
```

Calendar apps are time-sensitive. Core workflow should not hide `Date()` calls in business decisions because that creates flaky tests and timezone/day-change bugs.

### URL / OAuth Callback

```text
meetingbar:// URL / Google OAuth redirect
  -> URLHandler receives raw URL from AppKit
  -> AppRouteHandler parses route
  -> AppModel sends app action or active EventStore receives OAuth callback through a named owner
```

Parsing, routing and provider callback execution should be separate enough to test URL behavior without AppKit.

### Permissions / Capabilities

```text
Preferences Status / Onboarding / diagnostics
  -> PermissionReporter snapshot
  -> Calendar permission, notification authorization, Google auth, script access, sandbox assumptions
  -> UI renders status or AppModel decides next action
```

Permission state should be explicit. Onboarding and diagnostics should not rediscover permissions through random framework calls.

### User-Facing Messages

```text
technical failure
  -> owner maps error to AppMessage
  -> AppMessageCenter presents notification/alert/log-friendly text
```

This keeps provider/auth/StoreKit/script errors understandable for users without scattering `sendNotification` calls across feature code.

## Main Types

### AppModel

Owns `AppState`, receives `AppAction`, coordinates feature components.

Example actions:

```swift
enum AppAction {
    case launched
    case refreshRequested
    case providerChanged(EventStoreProvider, signOut: Bool)
    case calendarSelectionChanged(id: String, selected: Bool)
    case joinMeeting(eventID: String)
    case dismissEvent(eventID: String)
    case notificationResponse(NotificationResponseAction)
    case onboardingCompleted(EventStoreProvider)
    case screenLocked
    case screenUnlocked
}
```

Rule: `AppModel` coordinates, but complex decisions still live in policy files.

### AppClock

Small time boundary for workflow code.

Start simple:

```swift
struct AppClock {
    var now: @Sendable () -> Date
}
```

Use in:

- `AppModel` action handling;
- `EventManager` refresh ranges if they move out of direct `Defaults`;
- `EventSelection` / status presentation policies;
- notification and snooze planning;
- menu/status rendering decisions that decide current/running/upcoming state.

Do not inject this into every trivial view. The goal is deterministic workflow decisions and stable tests, not ceremony.

### AppSettings

`AppSettings.current` is the normal read boundary for persisted settings.

Do not add a new settings class unless the current shape becomes genuinely hard to maintain. The useful next step is write helpers for runtime-affecting settings:

```swift
extension AppSettings {
    @MainActor static func setProvider(_ provider: EventStoreProvider, clearsSelectedCalendars: Bool) { ... }
    @MainActor static func setSelectedCalendar(id: String, selected: Bool) { ... }
    @MainActor static func markOnboardingCompleted() { ... }
    @MainActor static func dismissEvent(_ event: MBEvent) { ... }
}
```

Rules:

- reads for app logic should use `AppSettings.current` or a sub-snapshot;
- runtime-affecting writes should use `AppSettings` helpers and usually go through `AppModel`;
- SwiftUI `@Default` can remain for simple persisted UI settings;
- do not create protocols for every settings type by default. Add fakes only where tests need them.

### EventManager

Final role: slim calendar/event orchestration owner.

Responsibilities:

- active provider;
- refresh calendars and events;
- provider switch;
- provider health;
- one refresh at a time;
- coalescing refresh triggers.

It can publish state during migration, but final ownership of app state should be in `AppModel`.

Guardrails:

- do not put filtering/selection rules here; use pure policies;
- do not open meetings here; use `MeetingOpener`;
- do not schedule notification side effects here; ask `AppModel`/`NotificationScheduler` to reconcile after state changes;
- do not own Preferences or Onboarding flow;
- avoid direct `Defaults` writes; receive/use `AppSettings` snapshots and write helpers;
- keep provider auth/API details in provider implementations.

Rename guardrail: do not rename to `CalendarSync` unless the code change needs it for clarity. The high-value work is slimming responsibilities, not type churn.

### EventStore

Existing provider boundary. Keep the name unless a future change proves it is actively confusing.

```swift
protocol EventStore {
    func signIn(forcePrompt: Bool) async throws
    func signOut() async
    func refreshSources() async
    func calendars() async throws -> [MBCalendar]
    func events(calendars: [MBCalendar], range: DateRange) async throws -> [MBEvent]
}
```

Implementations:

- `EKEventStore`
- `GCEventStore`

Provider API/auth details stay here. `AppModel`, Preferences, Onboarding and StatusBar should not know EventKit/Google implementation details.

### MeetingOpener

The only normal way to open, email, or run meeting-related side effects.

Responsibilities:

- open detected meeting link;
- fallback to event URL;
- notify missing link;
- run join script;
- email attendees;
- provider-specific URL transforms.

`MBEvent` must not open itself.

### NotificationScheduler

Owns system notification scheduling and in-app delayed actions.

Rules:

- `NotificationPlanner` remains pure.
- `NotificationCenterDelegate` converts system responses to `NotificationResponseAction`.
- Join/dismiss/snooze responses go through `AppModel`.

### SnoozeService

One owner for snooze behavior.

Responsibilities:

- convert a snooze action into a target trigger time;
- build a value description of the notification request;
- handle "until start" using the event start date and current time;
- call the notification scheduling adapter, not `UNUserNotificationCenter` directly from random files.

Pure timing/content rules should be testable without UserNotifications.

### Preferences

Do not build a ViewModel layer for every tab by default.

Allowed:

- SwiftUI `@Default` bindings for simple persisted UI settings;
- small view-local state for layout or picker UI;
- direct `AppSettings.current` snapshots for display-only status.

Must route through `AppModel` / `AppSettings` write helpers:

- provider picker;
- calendar selection;
- manual refresh/status actions;
- notification-related settings that require reconcile;
- settings that affect meeting opening behavior.

Preferences UI should not reach into `EventManager`, `AppDelegate`, or provider implementations directly.

### Onboarding

Keep existing `OnboardingHandler`, `OnboardingRouter`, and `OnboardingStep` if they remain understandable.

Responsibilities:

- provider selection UI;
- permission request UI;
- onboarding-specific error/auth state;
- completion handoff to `AppModel`.

Guardrails:

- do not duplicate app launch/provider switch logic here;
- do not create a second `EventManager` on completion;
- do not keep provider state separate from `AppModel`/`EventManager`;
- after completion, use normal runtime flow.

### StatusBarItemController

AppKit renderer and action forwarder.

Responsibilities:

- render status item title/icon from `AppState`;
- build menu from state snapshot;
- forward menu item actions to `AppModel.send`;
- open menu.

It should not:

- hold `weak var appdelegate`;
- read `eventManager`;
- call `event.openMeeting()`;
- mutate `Defaults` for important app behavior.

Dependencies can be simple closures:

```swift
struct StatusBarDependencies {
    let statePublisher: AnyPublisher<AppState, Never>
    let send: (AppAction) -> Void
    let openPreferences: () -> Void
    let openChangelog: () -> Void
    let quit: () -> Void
}
```

### MenuBuilder Event Item Helpers

`MenuBuilder.makeEventItem` is a real codebase hotspot and should be decomposed behind existing menu tests.

Suggested helpers:

- `makeEventTitle(...)`;
- `applyParticipationStyle(...)`;
- `applyTimeStyle(...)`;
- `populateDetailsSubmenu(...)`;
- `makeBookmarkActions(...)` / action item helpers;
- `makeAlternateMeetingLinksMenu(...)` can stay separate.

Rules:

- preserve behavior first;
- do not redesign the menu in this PR;
- keep tests close to branches already covered by `MenuBuilder` tests;
- decomposition should make future changes easier, not introduce a parallel renderer.

### AppIntent Bridge

AppIntents are app entry points, not a shortcut to `AppDelegate`.

Responsibilities:

- read current state through an `AppModel` accessor or injected action sink;
- send `AppAction` for join/dismiss;
- reuse the same nearest-event selection behavior as status bar;
- return values using pure formatters where possible.

It should not:

- call `StatusBarItemController`;
- cast `NSApplication.shared.delegate as? AppDelegate`;
- duplicate meeting-opening or dismiss logic.

### URLHandler / AppRouteHandler

`URLHandler` can stay as the AppKit-facing receiver for `meetingbar://` and OAuth callback URLs.

Add a small route owner if parsing grows:

```swift
enum AppRoute {
    case oauthCallback(URL)
    case openPreferences
    case unknown(URL)
}
```

Responsibilities:

- parse custom app URLs and OAuth redirects;
- forward OAuth callbacks to the active provider through a named owner;
- send app routes/actions to `AppModel` where possible;
- keep raw AppKit event handling in the app shell.

It should not:

- open windows directly after parsing;
- reach into `AppDelegate` from feature code;
- duplicate provider auth logic.

### PermissionReporter

One place to ask "what can the app currently do?"

Snapshot should cover:

- Calendar permission / EventKit access;
- notification authorization;
- Google auth state;
- script folder/access assumptions;
- sandbox/app-source facts that matter for diagnostics;
- optional LaunchAtLogin status if it remains user-visible.

Use it for:

- Onboarding next steps;
- Preferences Status tab;
- diagnostics;
- user support reports.

It should return values. UI decides how to display them; AppModel decides workflow actions.

### AppMessageCenter

One owner for user-facing error/success messages.

Responsibilities:

- map technical errors into localized user messages;
- present notifications/alerts through app adapters;
- provide logging-friendly message metadata without exposing private event data;
- keep success/failure messages for StoreKit, scripts, meeting opening, permissions and provider auth consistent.

It should not become a broad event bus. It is for user-visible messages only.

### WindowCoordinator

Owns AppKit window creation and focus behavior.

Responsibilities:

- Preferences window;
- Onboarding window;
- Changelog window;
- Fullscreen notification window;
- window close behavior that is UI-only.

It should not:

- switch providers;
- mark onboarding complete;
- mutate settings except through explicit model/settings calls;
- contain meeting/calendar/notification business rules.

Guardrail: `WindowCoordinator` must not become a second `AppDelegate`. It owns window lifecycle only. It receives closures/actions for anything that changes app behavior.

### PatronageService

Owns App Store / patronage integration using StoreKit 2.

Responsibilities:

- load products with `Product.products(for:)`;
- purchase with `Product.purchase()`;
- restore/check entitlements with `Transaction.currentEntitlements`;
- listen to `Transaction.updates` while the app is running;
- detect app source if this remains needed without relying on SwiftyStoreKit receipt helpers;
- return user-visible results to the app flow;
- persist patronage/app-source values through `AppSettings` write helpers.

It should not write `Defaults` directly in final architecture.

Guardrails:

- keep this small. This is a StoreKit 2 wrapper, not a broad state machine;
- verify old patronage purchases in App Store sandbox before removing SwiftyStoreKit;
- remove SwiftyStoreKit from Xcode SPM once the replacement is proven.

### DiagnosticsContext

Builds diagnostics reports from final state. Keep the existing name if it remains clear.

Inputs should be value snapshots:

- `AppState`;
- `AppSettings`;
- `ProviderHealth`;
- app version/build metadata;
- macOS metadata.

It should not keep old dependencies alive. If it needs provider information, pass a value snapshot.

### Structured Logging

Replace scattered `NSLog` with `os.Logger`.

Suggested categories:

- calendar/provider;
- meeting opening;
- notifications/snooze;
- StoreKit/patronage;
- onboarding;
- diagnostics;
- lifecycle/tasks.

Rules:

- classify user/event details as private unless they are safe operational labels;
- log enough to debug user issues without dumping calendar content;
- use signposts only where timing matters.

### SwiftPM Logic Boundary

Keep pure policy in `MeetingBarLogic` and macOS adapters in the app target.

Good candidates for `MeetingBarLogic`:

- event filtering/selection;
- status bar presentation;
- menu presentation value decisions;
- notification/snooze planning;
- meeting link detection and opening policy;
- Google parsing/policy that does not require AppAuth/URLSession;
- URL route parsing;
- user message mapping;
- script parameter formatting.

Keep in the app target:

- AppKit/SwiftUI views and controllers;
- EventKit;
- UserNotifications scheduling adapters;
- StoreKit;
- Defaults persistence;
- Keychain;
- AppAuth/OAuth presentation;
- AppleScript execution.

Each PR that extracts pure logic should ask: can this move into SwiftPM without making the boundary confusing?

### Dependency And Release Policy

Architecture includes project ownership for macOS release-sensitive files.

Track:

- third-party packages and why each remains;
- removal/migration plan for replaced dependencies;
- Xcode SPM package changes;
- entitlements;
- Info.plist URL scheme/OAuth assumptions;
- sandbox settings;
- App Store vs direct build behavior;
- release checklist for CI, signing, notarization/App Store, localization validation and smoke testing.

This should live in final non-temporary docs after PR 14.

### Scripts Ownership

AppleScript is a side effect, so ownership must be explicit:

- join-event script belongs to `MeetingOpener`;
- event-start scheduled script belongs to `NotificationScheduler` / action runner;
- script parameter formatting can stay as a pure helper with tests.

There should not be random UI code executing scripts directly.

### Localization / I18N

Localization is allowed to keep a small global helper if replacing it would add too much complexity.

If `I18N.instance` remains, document it as a deliberate exception:

- it is UI/infrastructure state;
- it is not business workflow state;
- preferred language changes still go through `AppSettings`/Preferences flow.

### Strict Concurrency

Swift 6 is already in use, so strict concurrency should be treated as architecture safety, not cleanup noise.

Work:

- make Xcode and SwiftPM strict concurrency settings explicit where supported;
- fix warnings before deeper refactors;
- document necessary framework interop exceptions such as EventKit/AppKit types;
- avoid adding new `@unchecked Sendable` or `nonisolated(unsafe)` without an owner comment and a future removal idea.

Strict concurrency should be a separate foundation PR because it can expose hidden ownership problems before the architecture work moves code around.

### Lifecycle And Cancellation

Every long-running task needs a clear owner:

- calendar refresh tasks: `EventManager`;
- status-bar minute tick: `StatusBarItemController` or a small ticker owned by AppDelegate;
- notification delayed action tasks: `NotificationScheduler`;
- snooze delayed/scheduled work: `SnoozeService` / notification scheduling adapter;
- StoreKit transaction updates listener: `PatronageService`;
- lifecycle observers: AppDelegate or a small observer object;
- provider auth flow: provider implementation.

Every owner needs a cancel/stop path for:

- app termination;
- provider switch;
- sign out;
- replacing a scheduler/action sink.

Do not create detached tasks without documenting who owns cancellation.

Task audit output should be a short table in the final architecture docs:

| Task source | Owner | Cancel path |
| --- | --- | --- |
| calendar refresh | `EventManager` | terminate/provider switch/sign out |
| status tick | `StatusBarItemController` or ticker owner | terminate/deinit |
| notification action tasks | `NotificationScheduler` | reconcile/sink replacement/terminate |
| Google auth/refresh tasks | `GCEventStore` | sign out/deinit |
| StoreKit updates | `PatronageService` | terminate/deinit |

## Testing Strategy

Use test levels that match the code:

- Pure policy tests: no AppKit host, fast `swift test`.
- AppModel tests: fake feature components, verify `AppState` and called actions.
- Component tests: fake event stores/settings/openers/schedulers.
- Adapter smoke tests: small tests around URL building/routing, OAuth callback routing, Google parsing, EventKit mapping, permission snapshots and StoreKit result mapping where possible.
- App composition tests: minimal checks that Preferences, Onboarding and StatusBar can be created with required dependencies.

The goal is not maximum test count. The goal is that a maintainer can safely change behavior and quickly know what broke.

## Test Coverage Contract

Coverage is a safety tool, not the architecture goal. Do not chase a global percentage by testing trivial wrappers. The important rule is: every migrated workflow gets tests around its new owner before the old path is removed.

Existing baseline:

- `make test-logic` runs SwiftPM tests with code coverage.
- `make test` runs SwiftPM tests and app-hosted Xcode tests with coverage.
- `make coverage-logic-report` reports hostless coverage for selected logic sources.
- `make coverage-app-report` reports Xcode target coverage.
- `make coverage-gate` currently uses a 90% logic coverage target as reporting-only, not a hard blocker.

Coverage targets during migration:

- Pure policies should have high unit coverage because they are cheap and stable: event filtering/selection, status bar presentation, menu presentation, notification planning, link detection, opening policy, script parameter formatting.
- `AppModel` should have scenario coverage for every important `AppAction`: launch, refresh, provider switch success/failure, calendar selection, join, dismiss, snooze, notification response, onboarding completion, URL route action.
- Time-sensitive decisions should use fixed `AppClock` / `now` inputs in tests.
- Feature components should have behavior coverage with fakes: `AppSettings` write helpers, slim `EventManager`, `MeetingOpener`, `NotificationScheduler`, `SnoozeService`, onboarding handoff, `PermissionReporter`, `AppMessageCenter`, `PatronageService`.
- Adapters should have smoke/edge tests, not exhaustive mocks of Apple frameworks: Google URL building/parsing, EventKit mapping, keychain query building, notification request building.
- AppKit/SwiftUI composition should have small smoke tests: Preferences, Onboarding and StatusBar can be created with all required dependencies.

Minimum migration rule:

- If a PR moves behavior to a new owner, add tests for that owner in the same PR.
- If a PR removes a legacy path, add a regression test that proves the new path handles the old behavior.
- If a behavior cannot be tested cheaply because of AppKit/EventKit/UserNotifications, extract the decision into a pure policy and test that policy.
- If a PR touches time, URL routing, permissions or user messages, add at least one deterministic test around the pure decision/mapping.
- Do not make coverage drop silently for logic sources touched by the PR. If it drops, explain why in the PR.

Suggested final bar:

- Keep `make coverage-gate` reporting-only until the migration stabilizes.
- After PR 14, consider making the logic coverage gate hard only for the migrated logic source set, not for the entire app target.
- Track coverage by owner/workflow, not only by total percentage. A lower global percentage with strong workflow coverage is better than a higher percentage that misses provider switch, notification response, or meeting opening.

## What Not To Do

- Do not redesign UI while doing architecture migration unless a PR explicitly targets a UI bug.
- Do not change calendar/provider behavior without a focused test or explicit release note.
- Do not introduce a DI container.
- Do not create protocols for every type.
- Do not move files first and call it architecture.
- Do not force every tiny preference toggle through `AppAction`.
- Do not keep two production paths for the same behavior.
- Do not add new global singleton state.
- Do not hide `Date()` / `Calendar.current` in core workflow decisions.
- Do not let URL parsing, OAuth handling and window opening collapse into one method.
- Do not scatter user-visible messages across random feature files.
- Do not leave `TODO: migrate later` without a concrete issue/PR step.
- Do not hide long-running `Task`s in random UI files.
- Do not let `EventManager` grow beyond calendar/event orchestration just because another feature needs a shortcut.

## Migration Invariants

Every PR should preserve these rules:

- app builds after the PR;
- behavior changes are either avoided or covered by a focused test/release note;
- one workflow moves at a time;
- old call sites are removed in the same PR when feasible, or named in the next concrete PR;
- new abstractions use MeetingBar words, not generic architecture words;
- temporary compatibility code has an owner and removal PR.
- pure logic is moved toward `MeetingBarLogic` when that reduces app-target coupling;
- release-sensitive files changed by the PR are named in the PR description.

## PR Plan

This is one redesign delivered as small PRs. Each PR should be reviewable in isolation, but the final target is the full architecture described above.

### Phase 1: Foundation

#### PR 0: Safety baseline

Fix known correctness issues before architecture work:

- `StatusTab` missing environment object / provider health access.
- Google Calendar calendar ID URL encoding.
- `AppSettings.empty` drift.
- `MenuBuilder` `|| true`.
- duplicate provider store-change subscriptions.
- provider switch sign-in failure updates provider health.
- README macOS version.

Checks:

- `make lint`
- `make validate-strings`
- `make test-logic-quiet`
- Xcode Debug build

#### PR 1: Warning-free Swift 6

Fix current Swift concurrency warnings:

- `LifecycleObserver`;
- `Shared.checkNotificationSettings`;
- `EventKitEventStore` completion handler;
- obsolete `KeyboardShortcuts.Name` Sendable extension;
- unnecessary `nonisolated(unsafe)`.

Exit: Xcode Debug build has no Swift concurrency warnings before strict checks are tightened.

#### PR 2: Strict concurrency, CI, testing harness, SwiftPM boundary

Scope:

- make strict concurrency checking explicit in SwiftPM/Xcode settings where supported;
- update CI triggers for Swift files, `Package.swift`, `MeetingBar.xcodeproj/project.pbxproj`, `XCConfig/**`, workflows, SwiftLint config, scripts and base localization;
- include `make validate-strings`, fast SwiftPM tests and Xcode build/test in CI;
- record current logic coverage baseline from `make coverage-logic-report`;
- add/standardize fakes for event stores, settings writes, meeting opening, notifications, StoreKit/patronage where feasible;
- add AppModel scenario test harness;
- add test helpers for fixed time via `AppClock` / injected `now`;
- add smoke tests for Preferences/Onboarding/StatusBar dependency creation;
- define test naming convention for workflow scenarios.
- document the SwiftPM logic boundary: what belongs in `MeetingBarLogic` and what must stay in the app target;
- create/update release-sensitive file checklist for project, entitlements, Info.plist URL scheme, sandbox, SPM packages and workflows.

Do not make coverage hard-blocking yet. During the migration it should be visible and reviewed.

Exit:

- new architecture PRs can add focused tests without inventing setup;
- strict concurrency warnings are visible and treated as work items;
- coverage changes are visible in PR review.
- pure logic boundary and release-sensitive file ownership are visible before deeper refactors start.

### Phase 2: Behavior Consolidation

#### PR 3: AppAction route extension + AppClock

Scope:

- extend `AppAction` for launch/refresh/provider change/calendar selection/join/dismiss/snooze/onboarding completion;
- route important actions through `AppModel.send`;
- introduce `AppClock` or consistent injected `now` for `AppModel` and newly moved workflow logic;
- remove hidden `Date()` from core paths touched by this PR;
- keep existing managers/renderers temporarily.

Exit:

- important Calendar/Preferences/StatusBar/AppIntent actions can be traced through `AppModel.send`;
- AppModel tests verify routing for refresh, provider change and calendar selection.
- time-sensitive AppModel tests use fixed time.

#### PR 4: AppSettings write helpers

Scope:

- keep `AppSettings.current` as the read boundary;
- add write helpers for provider selection, selected calendars, onboarding completion, dismissed events and patronage/app-source fields;
- update random runtime writes in `AppDelegate`, `AppModel`, StatusBar and AppStore/patronage code;
- keep simple SwiftUI `@Default` bindings for UI-only persisted settings.

Exit:

- runtime settings writes stop coming from random feature files;
- provider selection, calendar selection, dismiss/undismiss and onboarding completion use one documented write path;
- tests cover snapshot mapping, writes, defaults and migration-sensitive settings.

#### PR 5: External entry points + StatusBarItemController decoupling

Scope:

- remove `NSApplication.shared.delegate as? AppDelegate` from `AppIntent.swift`;
- route `meetingbar://` and OAuth callbacks through `URLHandler` / `AppRouteHandler` with testable parsing;
- remove `weak var appdelegate` / `setAppDelegate` from status bar code;
- inject state publisher and action closures;
- menu item actions send `AppAction`;
- nearest-event read/join/dismiss behavior is shared through `AppModel` route.

Exit:

```bash
rg "NSApplication.shared.delegate" MeetingBar/App/AppIntent.swift MeetingBar/UI/StatusBar
rg "weak var appdelegate|setAppDelegate" MeetingBar/UI/StatusBar
```

No production results.

Tests:

- menu actions send expected `AppAction`;
- AppIntent join/dismiss sends expected action;
- URL route parsing handles known app URLs, OAuth callback and unknown routes;
- title/icon rendering is driven by `AppState`;
- missing dependencies fail at composition/test time, not at runtime.

#### PR 6: WindowCoordinator

Scope:

- move Preferences, Onboarding, Changelog and fullscreen-notification window creation/focus/close out of `AppDelegate`;
- keep UI lifecycle in `WindowCoordinator`;
- keep provider switch, notification planning and app behavior outside `WindowCoordinator`.

Exit:

- `AppDelegate` asks `WindowCoordinator` to open/focus windows;
- window code does not mutate settings or app state directly except through explicit closures/actions;
- composition smoke tests verify windows receive dependencies.

#### PR 7: Onboarding through AppModel + PermissionReporter

Scope:

- keep existing `OnboardingHandler`, `OnboardingRouter`, `OnboardingStep` if they remain clear;
- remove `eventManager = await EventManager()` from onboarding completion flow;
- onboarding completion dispatches `AppAction` and uses normal provider switch/refresh route;
- onboarding marks completion through `AppSettings` write helper.
- add `PermissionReporter` snapshot for Calendar permission, notification authorization, Google auth state and script/sandbox assumptions that UI needs;
- make Preferences Status/diagnostics consume the permission snapshot where useful.

Exit:

- onboarding does not create a separate app initialization path;
- onboarding does not create a second `EventManager`;
- tests cover provider selection, auth/permission error state, completion and retry path.
- permission state is explicit and can be rendered without random framework calls in views.

### Phase 3: Domain Cleanup

#### PR 8: Data-only `MBEvent`

Scope:

- remove `MBEvent.openMeeting()`;
- remove `MBEvent.emailAttendees()`;
- remove direct `Defaults` from `MBEvent` initializer;
- remove localization/user-facing string decisions from model initialization where feasible;
- move meeting link detection into mapper/factory with explicit settings;
- replace `NSColor` in core model with simple color value if moving model into `MeetingBarLogic`.

Exit:

- `MBEvent.swift` has no AppKit/Defaults side effects;
- pure tests cover meeting link detection/fallback inputs that used to be hidden inside `MBEvent`.
- time/localization-sensitive derived values move to policies/formatters where they can receive explicit inputs.

#### PR 9: MeetingOpener exclusive + scripts ownership

Scope:

- route status bar join, shortcuts, notification response, fullscreen notification, AppIntent and email attendees through `MeetingOpener`;
- join script execution owned by `MeetingOpener` / script runner;
- event-start scheduled script execution owned by `NotificationScheduler` / action runner;
- Preferences "test script" action routes through the same script execution path;
- provider-specific URL transforms stay in one opening path.

Exit:

```bash
rg "openMeeting\\(" MeetingBar
rg "emailAttendees\\(" MeetingBar
rg "NSUserAppleScriptTask" MeetingBar
```

Only the named owner/integration files should remain.

Tests:

- opening link;
- event URL fallback;
- missing link notification;
- join script before opening link;
- email attendees;
- provider-specific URL transform;
- script parameter formatting and Preferences "test script" path.

#### PR 10: Notifications through AppModel + SnoozeService

Scope:

- `NotificationCenterDelegate` emits action values;
- `AppModel` routes join/dismiss/snooze;
- `NotificationActionRunner` no longer depends on `AppDelegate`;
- scheduling remains in `NotificationScheduler`;
- extract snooze timing/request logic into `SnoozeService` or pure snooze planner + adapter.

Exit:

- notification responses do not directly open meetings or mutate UI/controller state;
- snooze code is not duplicated across delegate/setup/scheduler/changelog references;
- tests cover join/dismiss/snooze routing, snooze +5/+10/+15/+30/until-start, and scheduler reconcile behavior.

#### PR 11: MenuBuilder.makeEventItem decomposition

Scope:

- decompose the large `makeEventItem` method without changing menu behavior;
- suggested helpers: participation styling, time/running styling, details submenu, attendee rendering, bookmark/action items;
- keep `MenuBuilder` as the renderer; do not create a parallel menu system.
- move pure event-item decisions toward `MeetingBarLogic` if they do not require AppKit types.

Exit:

- `makeEventItem` is small enough to scan;
- cyclomatic complexity drops materially;
- existing `MenuBuilder`/event item tests still pass and cover the moved branches.
- current/running/upcoming event item behavior is tested with fixed time.

### Phase 4: Modernization

#### PR 12: SwiftyStoreKit to StoreKit 2 + PatronageService

Scope:

- replace `AppStore.swift` free functions with a small `PatronageService`;
- use `Product.products(for:)` for product loading;
- use `Product.purchase()` for buying;
- use `Transaction.currentEntitlements` for restore/current access;
- listen to `Transaction.updates` while the app runs;
- persist patronage/app-source values through `AppSettings` write helpers;
- remove SwiftyStoreKit from Xcode SPM/project files after replacement.

Risk mitigation:

- verify in App Store sandbox that existing patronage purchases are visible through StoreKit 2 entitlements;
- keep product IDs unchanged;
- verify app-source behavior for direct/downloaded builds if that still matters.

Exit:

```bash
rg "SwiftyStoreKit|completeTransactions|purchaseProduct|restorePurchases" MeetingBar Package.swift MeetingBar.xcodeproj/project.pbxproj
```

No production results.

#### PR 13: Structured logging, AppMessageCenter, task ownership audit, release policy

Scope:

- replace scattered `NSLog` with `os.Logger`;
- add logger categories for calendar/provider, meeting opening, notifications/snooze, StoreKit/patronage, onboarding, diagnostics and lifecycle/tasks;
- classify event/user content as private unless clearly safe;
- introduce `AppMessageCenter` or equivalent simple owner for user-facing messages;
- move StoreKit/script/provider/meeting-opening success/failure messages behind message mapping;
- audit every `Task {}` and long-running task;
- add cancel paths for terminate, provider switch, sign out, scheduler sink replacement and StoreKit listener shutdown.
- finalize dependency/release policy: third-party package list, replacement/removal notes, entitlements, Info.plist URL scheme, sandbox assumptions, App Store/direct build differences.

Exit:

- `NSLog` is gone or documented as a deliberate exception;
- user-visible messages are mapped in one place or documented UI adapters;
- final docs include the task owner/cancel table;
- no detached/long-running task exists without an owner.
- final docs include dependency/release checklist.

### Phase 5: Final

#### PR 14: Final cleanup, EventManager slimming and docs

Scope:

- `AppDelegate` is composition root only;
- `EventManager` is slim calendar/event orchestration owner;
- `EventStore` remains provider boundary unless a concrete reason to rename appears;
- no old production path remains for opening meetings, notifications, snooze, settings writes, onboarding completion, URL/OAuth routing, user messages or patronage;
- final architecture is documented in non-temporary docs;
- temporary compatibility code is removed.

Final searches:

```bash
rg "Defaults\\[" MeetingBar
rg "NSApplication.shared.delegate" MeetingBar
rg "weak var appdelegate|setAppDelegate" MeetingBar
rg "openMeeting\\(" MeetingBar
rg "emailAttendees\\(" MeetingBar
rg "CalendarSync|CalendarProvider|DefaultsSettings|PreferencesModel|OnboardingModel" MeetingBar
rg "SwiftyStoreKit|completeTransactions|purchaseProduct|restorePurchases" MeetingBar Package.swift MeetingBar.xcodeproj/project.pbxproj
rg "NSLog\\(" MeetingBar
rg "Task \\{|Task\\(" MeetingBar
rg "NSUserAppleScriptTask" MeetingBar
rg "Date\\(\\)|Calendar\\.current" MeetingBar
rg "try!|as!" MeetingBar
rg "nonisolated\\(unsafe\\)|@unchecked" MeetingBar
rg "swiftlint:disable" MeetingBar
```

Every result must be handled:

- removed if it is legacy runtime coupling;
- moved to the named owner/integration file if the side effect is still needed;
- documented in `Final Allowed Exceptions` if it is a deliberate framework/tooling exception;
- for `EventManager`, verified as slim calendar/event orchestration only.
- for `Date()` / `Calendar.current`, verified as leaf UI/app-shell code or replaced with `AppClock`/explicit inputs.

## PR Review Checklist

For every PR:

1. Is the runtime flow easier to trace?
2. Did we remove at least one hidden dependency?
3. Is there one obvious owner for the changed behavior?
4. Did we avoid new abstract names that do not match MeetingBar behavior?
5. Are old call sites removed or scheduled for the next concrete PR?
6. Does a non-expert Swift maintainer know where to look next time?
7. Are tests close to the behavior that changed?
8. If coverage changed, is the change visible and explained?
9. Can the reviewer name the workflow test that protects the changed behavior?
10. If the PR touches time, URL routing, permissions, messages, dependencies or release-sensitive files, is the owner/checklist updated?

## Contributor Rule Of Thumb

Before changing behavior:

- If it is a user/system event, send an `AppAction`.
- If it is persisted settings, read through `AppSettings.current`; route runtime writes through `AppSettings` helpers / `AppModel`.
- If it is calendar/event orchestration, use slim `EventManager`.
- If it is provider API work, use `EventStore`.
- If it opens or emails a meeting, use `MeetingOpener`.
- If it schedules notifications, use `NotificationScheduler`.
- If it snoozes a notification, use `SnoozeService`.
- If it purchases/restores patronage, use `PatronageService`.
- If it depends on current time, use `AppClock` or pass `now` explicitly.
- If it handles app URLs/OAuth callbacks, use `URLHandler` / `AppRouteHandler`.
- If it reports permissions/capabilities, use `PermissionReporter`.
- If it shows user-facing errors/success messages, use `AppMessageCenter`.
- If it is pure logic, try to put it in `MeetingBarLogic`.
- If it decides what should happen, put it in a pure policy and test it.

This plan is intentionally boring. The goal is not architectural purity; the goal is a MeetingBar codebase where behavior has one owner, side effects are obvious, and a maintainer can safely ship small PRs.
