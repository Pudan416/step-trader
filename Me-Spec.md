# Me — simplification, and the collapse to three tabs

**Date:** 2026-08-08
**Status:** Draft, awaiting review
**Scope:** Spec 0c of the redesign stack

---

## Why this exists

Me is the most crowded screen in the app and the least used. It carries a radar
chart of three dimensions, weekly rings, a reflection, a breakdown, and a top
consumers list — a dashboard for a product whose whole argument is that you
should look at your life rather than a dashboard.

This spec strips it to four things worth knowing, folds the History tab into it,
and moves Settings to a button. That collapses the tab bar from five
destinations to three: **canvas, feeds, me**.

It is the third of the pre-foundation specs, beside `Happenings-Spec.md` and
`Feeds-Spec.md`. It depends on the happenings rework — the radar it removes is
built on the categories that spec deletes — so it lands after it.

---

## Three entities, named

The product's vocabulary settles here. Everything a day is made of is one of
three things:

**sleep** · **steps** · **happenings**

"Happening" replaces "activity", "piece", "option" and "moment" in both the
interface and the code. `Happenings-Spec.md` and `Happenings-Brief.md` are
written in these terms. The daily formula reads:

```
day = sleep(20) + steps(20) + happenings(60) = 100
```

The one deliberate exception is the analytics event `piece_selected`, which
keeps its name so historical dashboards stay continuous.

---

## The screen

Top-right: a **settings button**. `SettingsSheet` already works as a standalone
sheet — it was only ever a tab because there was room for one.

No energy bar. `StepBalanceCard` is currently a global overlay in `MainTabView`
drawn over every tab; it becomes conditional on canvas and feeds only. Me is
where you look back, not where you check your balance.

Then, in order:

### 1. This week, in three numbers

Average sleep, average steps, and the happenings that came up most. Three
entities, three readings, no radar and no rings.

### 2. Connected apps

Each connected app with the colors it cost you this week.

**Colors, not minutes.** Real per-app screen time is not readable by an app —
iOS exposes it only through a `DeviceActivityReport`, a view rendered by a
separate extension in another process whose numbers cannot be pulled into the
app's own model. There is no such extension in the project.

The existing `topAppsSection` does show minutes, but they are derived from the
payment log — `minutes10` → 10, `minutes30` → 30 — which counts minutes
**bought**, not minutes **used**. Since a window is spent by usage and is
routinely left unfinished, that number systematically overstates. It is replaced
rather than kept.

`appStepsSpentByDay` already holds exact per-app color spend by day. That is what
this block shows.

### 3. The calendar

Past days, scrolling horizontally back into the past. Tapping a day opens that
day's canvas as a poster.

Most of this exists. `HistoryView` already renders past days grouped by month and
opens `DayCanvasViewerView`, described in its own source as a pixel-faithful
render of the persisted canvas. The work is re-laying it out as a horizontal
scroll and moving it into Me — not rebuilding it.

**The Pro gate on history is dormant, and must survive the move anyway.**
`HistoryView` blurs tiles older than `SubscriptionGate.freeHistoryDayCount`
behind a Pro badge. That gate does not fire today —
`SubscriptionGate.allFeaturesUnlocked` is `true`, `isPro` is unconditionally
true, and the app ships free. The constant is a documented kill-switch meant to
be flipped back, so the re-layout must carry the logic across rather than
discard it as unreachable.

---

## Tabs: five to three

| Today | After |
|-------|-------|
| 0 Canvas | 0 Canvas |
| 1 Feeds | 1 Feeds |
| 2 Me | 2 Me |
| 3 History | folded into Me as the calendar |
| 4 Settings | button, top-right of Me |

Nothing is lost. Notes are unaffected — `ManualsPage` is already reached from
inside `SettingsSheet` rather than from a tab, despite what `README.md` claims.
The README needs correcting as part of this work.

`MainTabView.Tab` is a raw-value enum persisted through
`@SceneStorage("selectedTab")`. Removing cases 3 and 4 means a stored `3` or `4`
from a previous launch resolves to nothing. Clamp out-of-range stored values to
`.canvas` on read.

---

## What is removed

| Piece of Me | Why |
|-------------|-----|
| Radar chart and its axes | Built on body / mind / heart, which `Happenings-Spec.md` deletes |
| `MeAxisDetailView` | Opens a dimension that no longer exists |
| Weekly rings | Replaced by the three-number summary |
| Reflection block | Not part of the four things worth knowing |
| Per-app minutes bars | Replaced by color spend, which is exact |

`MeView.swift` is 908 lines and most of that is radar layout mathematics —
`RadarLayout`, `RadarCenterKey`, `radarBackground`, `radarTapOverlay`, the
`radarSnaps` / `radarSummary` / `radarAxes` state. It goes with the radar.
`MeViewSupport.swift` should be re-examined once it does.

---

## Dependencies

This spec cannot land before `Happenings-Spec.md`. The radar, the axis detail
view and the week summary all read `EnergyCategory`; removing them separately
would mean writing category-based code twice.

`Feeds-Spec.md` is independent of this one and can proceed in parallel.

---

## Acceptance criteria

- [ ] The tab bar has exactly three destinations
- [ ] A stored `selectedTab` of `3` or `4` from a previous version opens the canvas rather than crashing or showing an empty tab
- [ ] `StepBalanceCard` appears on canvas and feeds, and not on me
- [ ] Settings opens from a button at the top right of Me
- [ ] Everything previously reachable from the Settings tab is still reachable, including `ManualsPage`
- [ ] Me shows average sleep, average steps, and the week's most frequent happenings
- [ ] The connected apps block shows exact color spend per app, sourced from `appStepsSpentByDay`
- [ ] No screen reports minutes spent per app
- [ ] The calendar scrolls horizontally into the past and opens a day's poster on tap
- [ ] With `allFeaturesUnlocked` temporarily `false`, the calendar still blurs days beyond `freeHistoryDayCount` behind the Pro badge
- [ ] `README.md` no longer describes a Notes tab or a five-tab structure
