# Feeds — flat list, unlock sheet, unlock timer

**Date:** 2026-08-08
**Status:** Draft, awaiting review
**Scope:** Spec 0b of the redesign stack, sibling to `CanvasPieces-Spec.md`

---

## Why this exists

The Feeds tab is built on a paper-ticket metaphor: apps are gathered into
groups, each group renders as a ticket with a sticker theme, and unlocking runs
through a ticket's settings. The metaphor is charming and it is in the way. To
open Instagram you navigate a stack of tickets rather than tapping Instagram.

This spec flattens the surface: one scrolling list, tap an app, choose how long,
watch the time run down.

It sits beside the canvas pieces rework as spec 0b. The two are independent —
neither blocks the other — and both precede the foundation and shell work.

---

## What the user sees

**The list.** One vertical scroll. Each row is a thing you can open:

- A single app renders as its icon with its name.
- A group renders as a cluster of two or three overlapping icons with the
  group's name. Groups stay — this is a new view onto them, not their removal.
- Anything currently blocked carries a lock badge. The badge is identical for
  single apps and groups.

**The unlock sheet.** Tapping any locked row opens a sheet offering three
windows — 10, 30 and 60 minutes — priced at 4, 10 and 20 colors. Both the
intervals and the prices are unchanged from today. The sheet should read like
the PayGate, warm and deliberate, but it is Nowhere's own screen and has nothing
to do with the system shield.

**The timer.** Choosing a window opens a timer screen: a soft radial arc that
depletes as time passes, remaining time in large monospaced digits, and beneath
it the list of apps this window covers. Tapping an app in that list launches it.

There is no pause control. A window, once bought, runs.

---

## Platform constraints

Three things about iOS shape this design and are not negotiable. They are
recorded here because each one looks like an implementation detail and is
actually a design boundary.

### App icons cannot be extracted

`FamilyActivitySelection` yields opaque `ApplicationToken` values. There is no
API to read an app's name or icon from one — Apple closed this deliberately so
apps cannot enumerate what is installed. The only way to render a real icon is
the FamilyControls-provided SwiftUI `Label(token)`, which the system draws in
its own process. It cannot be recolored, masked, or placed inside a custom
shape.

`TargetResolver` already works around this with a registry of known apps
(Instagram, TikTok, YouTube, Telegram and others), each carrying a bundled
`imageName` asset.

**Decision:** registry apps render with our own assets and full styling control.
Everything else renders as an unstyled system `Label`. The list is visually
mixed as a result. This is accepted — the alternative is either maintaining
asset parity with the App Store forever, or giving up styling for every app.

### Nothing can draw over another app

While the user is inside Instagram, Nowhere cannot render anything on top. The
only surface visible from another app is a **Live Activity** — Dynamic Island
and Lock Screen.

So the timer exists twice: as the full screen inside Nowhere, and as a Live
Activity outside it. The full screen is where the design lives; the Live Activity
is where it is actually useful.

### DeviceActivity monitors are capped

Each group registers its own monitor, `usageBudget_<groupId>`, in
`DeviceActivityCenter`. The framework caps how many activities can be monitored
at once — around twenty, and the current code does not handle exceeding it.

Today this never surfaced because groups are few and deliberate. A flat list
invites adding apps one at a time, and each one added as its own group is
another monitor.

**This must be measured on a physical device before the list ships.** If the cap
is real at twenty, the list needs either a stated maximum or a strategy for
sharing one monitor across concurrently unlocked entries. Until measured, treat
the flat list's scale as unknown, and add explicit handling for the
`excessiveActivities` failure rather than letting `startMonitoring` fail silently.

---

## Live Activity

New infrastructure — ActivityKit does not appear anywhere in the project today.
`UnlockWidget` is a plain WidgetKit extension with a timeline provider, which is
a different mechanism.

Required:

- `NSSupportsLiveActivities` in `Steps4/Info.plist`
- An `ActivityAttributes` type carrying the entry's name, its icon identity, and
  the window's end date
- Live Activity views added to the existing widget extension
- Start on unlock, from the app, in the PayGate flow
- End on expiry and on early close

**Render the countdown with `Text(timerInterval:countsDown:)`.** Live Activities
cannot be updated once per second — the system throttles updates hard. Passing
the interval lets the system animate the countdown itself with no updates at
all. An implementation that pushes per-second updates will appear to work in
development and then stall on a real device.

Deployment target is iOS 18, comfortably above ActivityKit's 16.1 requirement.

---

## Open question: the timer screen is light

The reference for the timer is cream-backgrounded with a warm orange arc and
black digits. The app ships a single **night** theme — `#222831` background,
near-white text — and `design.json` lists `night` as the only supported theme.

Dropping a light screen into a dark app is a deliberate choice or a mistake, and
which one it is has not been decided. Two coherent readings:

1. The timer is intentionally a bright interruption — the one screen that
   doesn't belong to the app's night, marking that you have left the canvas and
   entered borrowed time.
2. The reference is a style study and the timer should be restyled onto the
   night theme, with the warm arc reading against a dark background.

This needs an answer before the screen is built. It also affects the Live
Activity, which should match whatever the full screen does.

---

## Scope

**In scope:** the list, the unlock sheet, the timer screen, the Live Activity,
launching apps from the timer via `TargetResolver` schemes, and
`excessiveActivities` handling.

**Unchanged:** `AccessWindow` keeps `minutes10` / `minutes30` / `hour1`. Costs
stay 4 / 10 / 20. No enum migration, no repricing. `TicketGroup` keeps its shape,
including manual group creation.

**Out of scope:** design tokens, component library, tab structure. The shield
extensions are untouched — this changes how a window is bought and displayed,
not how blocking works.

---

## Principal files

| File | Role |
|------|------|
| `StepsTrader/Views/AppsPageSimplified.swift` (452 lines) | The current ticket stack. Becomes the flat list |
| `StepsTrader/Views/PayGateView.swift` | Existing unlock UI. The new sheet should reuse its flow, restyled |
| `StepsTrader/AppModel+PayGate.swift` | Monitor lifecycle, `usageBudget_<groupId>`. Gains Live Activity start/stop and `excessiveActivities` handling |
| `StepsTrader/TargetResolver.swift` | Registry of known apps — assets for the list, schemes for launching from the timer |
| `StepsTrader/Models/TicketGroup.swift` | Unchanged |
| `UnlockWidget/` | Gains the Live Activity views |
| `Steps4/Info.plist` | Gains `NSSupportsLiveActivities` |

---

## Acceptance criteria

- [ ] Feeds is a single scrolling list; no ticket stack remains
- [ ] A registry app shows its bundled asset; a non-registry app shows a system `Label`
- [ ] A group shows as a clustered icon with its name, and can still be created manually
- [ ] Locked entries carry a lock badge, identical across singles and groups
- [ ] Tapping a locked entry offers 10 / 30 / 60 minutes at 4 / 10 / 20 colors
- [ ] Buying a window opens the timer screen
- [ ] The timer lists the window's apps, and tapping one launches it
- [ ] A Live Activity appears on unlock and shows remaining time in the Dynamic Island
- [ ] The Live Activity counts down without per-second updates
- [ ] The Live Activity ends on expiry and on early close
- [ ] Exceeding the DeviceActivity cap surfaces a real error instead of failing silently
- [ ] **Measured on a physical device:** the number of concurrent monitors before
      `startMonitoring` refuses, recorded in this document
