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
depletes as the window is spent, remaining time in large monospaced digits, and
beneath it the list of apps this window covers. Tapping an app in that list
launches it, through the schemes already registered in `TargetResolver`.

There is no pause control. The screen shows time and launches apps, nothing else.

The screen uses the app's night theme. The reference image for this screen is
light, but it was supplied as an illustration of how time is *displayed* — the
depleting arc and the large monospaced digits — not as a color direction.

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

### DeviceActivity monitors are capped at twenty

Each group registers its own monitor, `usageBudget_<groupId>`, in
`DeviceActivityCenter`. **Twenty** activities is the documented ceiling for an
app and its extensions combined; beyond it `startMonitoring` throws
`DeviceActivityCenter.MonitoringError.excessiveActivities`. Two neighbouring
limits matter as well: a selection holds at most **50 application tokens**, and
a schedule's interval cannot be shorter than **15 minutes**.

The current code catches the throw and stops the monitor, but surfaces nothing
to the user. That is acceptable today because groups are few and deliberate.

The ceiling counts **concurrently monitored windows**, not rows in the list, so
keeping groups visible means a user has to hold twenty windows open at once to
reach it. That is unlikely but not impossible, and it must fail legibly rather
than leaving an app silently unblocked. Add real handling for
`excessiveActivities` with a user-facing message.

---

## The window is spent, not elapsed

This is the single most important thing to understand before building the timer,
and it is easy to miss because the code reads like a schedule.

The `DeviceActivitySchedule` spans a full day, `0:00:00`–`23:59:59`. It exists
only to satisfy the framework's 15-minute minimum. The actual window is measured
by `DeviceActivityEvent` thresholds in **minutes of app usage**:

```swift
threshold: DateComponents(minute: m)
```

So "10 minutes" means ten minutes of actually looking at the app. Put the phone
down and the window stops draining. This is deliberate and it stays.

Two consequences the design has to absorb:

**A wall-clock countdown would be a lie.** Digits melting away while the phone
lies face-down would misreport what the user has left.

**The real signal arrives once a minute.** `usageBudgetTick_<groupId>_<m>` events
already fire per minute of usage. The honest indicator therefore steps a minute
at a time. It does not flow. Do not interpolate between ticks to make it look
smooth — the arc would run ahead of the truth and then jump backwards when the
next tick lands.

Note also that a 60-minute window currently registers around 64 events (59
per-minute ticks, up to four widget milestones, one completion). The documented
cap is on activities, not events, so this is legal — but it is heavy, and worth
revisiting if the tick events prove unreliable.

---

## Live Activity

New infrastructure — ActivityKit does not appear anywhere in the project today.
`UnlockWidget` is a plain WidgetKit extension with a timeline provider, which is
a different mechanism.

Required:

- `NSSupportsLiveActivities` in `Steps4/Info.plist`
- An `ActivityAttributes` type carrying the entry's name, its icon identity, and
  the remaining usage minutes
- Live Activity views added to the existing widget extension
- Start on unlock, from the app, in the PayGate flow. Live Activities may only be
  *started* while the app is in the foreground, which the unlock flow satisfies
- End on expiry and on early close

**Do not use `Text(timerInterval:countsDown:)`.** It is the usual answer for
Live Activity countdowns and it is wrong here: it counts wall-clock time, and
this window is spent by usage. The Live Activity has to be updated on each
per-minute tick instead.

### Resolved: the monitor extension cannot update the Live Activity

The ticks arrive in the `DeviceActivityMonitor` extension. The app is not
running at that moment — the user is inside Instagram. So the update has to come
from the extension.

**Answer: no.** Measured on a physical iPhone 15 Pro, iOS 26.6, 2026-08-09.
The extension cannot even *see* the Live Activity, so updating it is moot.

The production callback fired exactly as designed, and the probe inside it
reported:

```
eventDidReachThreshold: spikeUsageTick for activity spikeUsage
spike[monitor:eventDidReachThreshold] visible=0 wanted=BBB557AF-… matched=false
spike[monitor:eventDidReachThreshold] RESULT=no-activities-visible elapsed=0.00s
```

`Activity<…>.activities` returned an empty list inside the extension while the
activity was demonstrably alive — visible in the Dynamic Island, its id stored in
the shared defaults. This is the empty-`activities` failure this section
anticipated, now confirmed for `DeviceActivityMonitor` and not merely for widget
extensions.

Two alternative readings are ruled out by the same line. `elapsed=0.00s` rules
out the extension process being torn down mid-`await`: it never reached the
update. `visible=0` alongside `matched=false` rules out a stale id: the list was
empty, not mismatched.

Not measured: whether `intervalDidStart` behaves differently. The retained log is
capped at 30 entries and the relevant lines had rolled off. It runs in the same
process under the same entitlement, so there is no reason to expect otherwise —
but it is untested, and should not be claimed as tested.

**Therefore the fallback applies.** The Live Activity shows the window's size and
a `staleDate`, refreshing only when the app next runs — degraded, but honest
about what it knows. Do not ship a Live Activity that silently displays a stale
number as if it were live, and do not build a timer that assumes per-minute
updates reach the Lock Screen.

Frequency was the second risk: iOS throttles frequent updates against an
undocumented budget, and sixty updates across an hour was within reach of it.
**This is now moot** — the extension cannot update at all, so there is no update
frequency to throttle. `NSSupportsLiveActivitiesFrequentUpdates` is set in
`Steps4/Info.plist` and costs nothing, but it buys nothing either until updates
have some path to originate from.

The harness that produced this answer, and how to re-run it, is in
`Feeds-Spike.md`.

Deployment target is iOS 18, comfortably above ActivityKit's 16.1 requirement.

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
- [ ] Buying a window opens the timer screen, in the night theme
- [ ] The timer lists the window's apps, and tapping one launches it
- [ ] The timer does not move while the covered apps are unused — verified by
      leaving the phone idle with a window open and confirming nothing drains
- [ ] The arc steps on tick boundaries and never runs backwards
- [ ] A Live Activity appears on unlock and shows the window's size in the Dynamic Island
- [ ] The Live Activity carries a `staleDate` and visibly marks itself stale rather
      than presenting an unrefreshed number as current
- [ ] The Live Activity refreshes when the app next reaches the foreground
- [ ] The Live Activity ends on expiry and on early close
- [ ] Exceeding the DeviceActivity cap surfaces a user-facing error rather than
      leaving an app silently unblocked

### Spike — done, 2026-08-09

- [x] **On a physical device:** does `Activity.update` succeed from inside the
      `DeviceActivityMonitor` extension? **No.** The extension sees an empty
      `Activity.activities` and never reaches the update. See the resolved
      section above and `Feeds-Spike.md`.
- [x] ~~Confirm per-minute updates still land in the final minutes of a 60-minute
      window~~ — moot. There are no extension-originated updates to throttle.
