# Current product

Implementation is authoritative. This page describes the integrated app, not earlier proposals.
For tone and product intent, read [PRODUCT.md](../PRODUCT.md).

## Daily loop

Sleep, activity and happenings create up to 100 colors per custom day:
20 from sleep, 20 from activity and 60 from happenings. Activity currently uses
HealthKit step counts. Missing activity data grants a 5-color fallback; real data
replaces it. Sleep has a 10-color fallback after six hours from the day boundary.
Refreshing does not accumulate extra fallback grants.

The configured day boundary can differ from calendar midnight. Existing `steps*`
and `energy*` storage names are compatibility identifiers, not a second currency.

## Surfaces

- **Canvas** — the current day's saved composition, happenings palette, artwork interaction,
  Remix, generative music and export. Historical Canvas formats remain renderable.
- **Feeds** — selected app groups, color prices and access windows. Purchases and actual
  Screen Time usage coordinate through the app, App Group and Screen Time extensions.
- **Me** — recent-week context and the archive. An empty day is not a recorded zero or a
  saved artwork. Settings opens from Me.
- **Settings** — permissions, appearance, goals, widgets/wallpaper, account and app information.
  Developer controls have separate build guards.

Onboarding introduces these surfaces in context. Its implementation lives in
`Nowhere/Views/Onboarding/`; check the current coordinator and tour transitions
when changing the sequence rather than using an old slide specification.

## Music and artwork

The production Canvas uses native Metal artwork with versioned deterministic recipes.
Four sound worlds and their moods are selected from the bundled catalogs. Planners
build music from the day's inputs; the playback engine owns audio execution.
The same saved day must not change because a catalog was casually reordered.
See [Canvas ownership](architecture/canvas-components.md) and [audio](audio.md).

## Widget and wallpaper suggestions

Widget and wallpaper offers first become eligible after cold launches 5 and 7,
respectively, after onboarding. Wallpaper also needs a saved Canvas. Suggestions
and App Store review requests share a 48-hour cooldown; at most one suggestion
appears per process session, and never together with a review request.

“Maybe later” or swipe dismissal permits one repeat after at least seven days and
Canvas visits on three distinct later calendar days. The dismissal day does not
count. Canvas must be foregrounded and visible without an intervening sheet or
handoff. A second dismissal, accepting the settings link, a confirmed widget or a
successful wallpaper export ends the corresponding automatic offer. An unknown
WidgetKit response does not prove absence. Existing v1 seen flags remain terminal;
Developer “Reset Feature Tips” clears the history.

## System integration

- HealthKit reads steps and sleep; authorization and real data vary by user/device.
- Family Controls, Device Activity and ManagedSettings implement app selection and shielding.
- App Group `group.personal-project.StepsTrader` shares state with the extensions.
- `stepstrader://` and `steps-trader://` are compatibility URL schemes.
- Authentication and cloud synchronization preserve local Canvas recovery and ownership.

Do not remove migration paths, stored values or resources just because the current
UI no longer offers them for new selections.
