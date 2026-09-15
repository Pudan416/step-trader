# Nowhere (iOS, SwiftUI)

Your life makes colors. Your feeds cost them.

An iOS app where real-world activity — sleep, activity and happenings — produces **colors**. Colors are what you spend to open your feeds.

## Core Loop

1. **Live** — Sleep, walk, log the happenings of your day.
2. **See** — Your canvas fills up. Colors accumulate.
3. **Spend** — When you want into your feeds, spend colors through the PayGate.

A day is `sleep(20) + activity(20) + happenings(60) = 100`.

Activity currently uses Apple Health step counts. An empty query or unavailable Health access grants 5 colors for the day; real data replaces that fallback. Sleep keeps its existing 10-color fallback after six hours from the day boundary. Refreshing does not accumulate gifts. Persisted `steps*` keys retain their names for compatibility with saved canvases, widgets, and Health measurements.

## Tabs

| Tab | View | Purpose |
|-----|------|---------|
| 0 (default) | Canvas | Generative canvas + the happenings palette |
| 1 | Feeds | App blocking groups — create tickets, set tariffs, configure time windows |
| 2 | Me | This week in three numbers, connected apps, the calendar of past days |

Settings is a button at the top right of Me, not a tab. **Notes from Kosta** —
the wall texts — is reached from inside Settings (`Info` → `Notes from Kosta`).

## Targets

| Target | Description |
|--------|-------------|
| **Steps4** | Main iOS app (display name: **Nowhere**) |
| **DeviceActivityMonitor** | Extension — tracks app usage events and shield rebuilds |
| **ShieldConfiguration** | Extension — renders custom shield UI |
| **ShieldAction** | Extension — handles shield button taps and unlock flow |
| **Steps4Tests** | Unit tests |
| **Steps4UITests** | UI tests |

## Capabilities / Permissions

- **HealthKit (Read)** — step count and sleep hours
- **Family Controls + Device Activity + ManagedSettings** — app selection, monitoring, and shielding
- **App Group** — `group.personal-project.StepsTrader` (shared state between app + extensions)

ManagedSettings shielding is active. Blocking/unblocking flows through ticket settings, DeviceActivity, and the shield extensions.

## Project Structure

```
StepsTrader/
├── Views/              SwiftUI views (MainTabView, GalleryView, MeView, etc.)
├── Models/             Data models (DailyEnergy, CanvasElement, AccessWindow, etc.)
├── Services/           Business logic (HealthKit, Auth, Supabase, Persistence, etc.)
├── Stores/             State management (BlockingStore, HealthStore, UserEconomyStore)
├── Intents/            App Shortcuts and intents
├── Utilities/          Helpers (SharedKeys, ColorConstants, AppLogger, etc.)
├── Metal/              Metal shaders for canvas rendering
├── Resources/          In-app documentation and markdown content
└── Assets.xcassets/    App icons and images

DeviceActivityMonitor/  Extension target
ShieldAction/           Extension target
ShieldConfiguration/    Extension target
Steps4/                 App bundle resources (Info.plist, entitlements)
Steps4Tests/            Unit tests
Steps4UITests/          UI tests
admin-panel/            Next.js admin dashboard (Supabase-backed)
tg-admin/               Cloudflare Worker Telegram admin bot
supabase/               Database migrations
OnboardingPreview/      Local SPM package — Xcode Previews for onboarding slides.
                        `Sources/OnboardingStoriesView.swift` is a SYMLINK to
                        `StepsTrader/Views/OnboardingStoriesView.swift` (single
                        source of truth). Don't "fix" the symlink — the package
                        target wouldn't compile without it.
```

## Domain vocabulary

Three prefixes recur across the codebase — once you know them the names self-document:

- **`Energy*`** — model layer. `EnergyCategory` (body / mind / heart), `EnergyOption`
  (a single activity card with id + title + icon), `EnergyRoutine` (a named template),
  `EnergySignature` (visualisation type), etc.
- **`daily*`** — state that's *anchored* to the user's custom day boundary
  (`dayEndHour` / `dayEndMinute` in settings, not calendar midnight). E.g.
  `dailyEnergyAnchor` (the persisted day-start timestamp), `dailyCanvasSlots`
  (today's 4 canvas slots), `dailyMoments` (today's ephemeral one-off events).
- **`spent*`** — balance deductions. `spentStepsToday` is base-energy used,
  `appStepsSpentToday` is per-app/per-group cost dictionaries. The "Pay" /
  "PayGate" flows write into these.

Energy is *earned* from activity + sleep + happenings, *spent* via PayGate to unlock
blocked apps. The custom day boundary determines when all the `daily*` keys reset.

## Deep Links

Schemes registered in `Steps4/Info.plist`:
- `stepstrader://...`
- `steps-trader://...`

Examples (see `StepsTrader/AppModel.swift`):
- `steps-trader://pay?target=<bundleId|alias>`
- `steps-trader://guard?target=<bundleId|alias>`

## Supabase

Keys used in `Steps4/Info.plist`:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Move to `.xcconfig` (Debug/Release) or use CI secrets before shipping.

## Run / Build

FamilyControls/DeviceActivity require a **physical device** (entitlements + system limitations).

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

## Admin Tools

- **admin-panel/** — Next.js dashboard for user management, global stats, and energy ledger. Password-protected, uses Supabase service role key.
- **tg-admin/** — Telegram bot on Cloudflare Workers for interactive admin commands (`/stats`, `/user`, `/grant`, `/ban`, etc.) with LLM-powered natural language queries.

## Widget and wallpaper suggestions

First offers become eligible after cold launches 5 (widget) and 7 (wallpaper), once onboarding is complete. Wallpaper also requires a saved Canvas. All suggestions and App Store review requests share a 48-hour cooldown; a process session shows at most one suggestion and never combines it with a review request.

“Maybe later” and swipe dismissal allow one repeat after at least seven days and Canvas visits on three distinct subsequent calendar days. The dismissal day does not count. Canvas must be foregrounded and visible, without Settings, a feature suggestion, PayGate or handoff protection covering it. The second dismissal ends automatic offers. Accepting the settings link also ends that offer. WidgetKit-confirmed widgets and a successfully used wallpaper export suppress their respective offers. An unknown WidgetKit response does not mean the widget is absent.

History persists locally. Existing v1 seen flags remain terminal because they do not record whether the user accepted or dismissed. Developer “Reset Feature Tips” clears this history.
