# Implementation brief — Me, and the collapse to three tabs

Self-contained brief for simplifying the Me tab and reducing the tab bar from
five destinations to three. Design rationale lives in `Me-Spec.md`.

Read `Happenings-Brief.md` §1 for shared project context and the build command.

**Sequencing:** this work depends on the happenings rework. The radar it removes
is built on the `EnergyCategory` model that `Happenings-Brief.md` deletes; doing
them separately means writing category-based code twice. `Feeds-Brief.md` is
independent and can run in parallel.

---

## 1. The problem

Me is the most crowded screen in the app and the least used. A radar chart of
three dimensions, weekly rings, a reflection, a breakdown, a top consumers list —
a dashboard for a product whose entire argument is that you should look at your
life instead of a dashboard.

`MeView.swift` is 908 lines, and the majority of it is radar layout mathematics.

---

## 2. The vocabulary

The product settles on three entities. Everything a day is made of is one of:

**sleep** · **steps** · **happenings**

"Happening" is the name in both the interface and the code — it replaces
"activity", "piece", "option" and "moment". The daily formula reads:

```
day = sleep(20) + steps(20) + happenings(60) = 100
```

One deliberate exception: the analytics event `piece_selected` keeps its name so
historical dashboards stay continuous. Do not rename it.

---

## 3. The screen, top to bottom

**Top right: a settings button.** No new plumbing needed — `SettingsSheet`
already takes `embeddedInTab: Bool = false` and works standalone; the flag only
controls a `topCardHeight` inset. Present it as a sheet with the default.

**No energy bar.** `StepBalanceCard` is currently a global overlay in
`MainTabView`, drawn over every tab. It becomes conditional on canvas and feeds.
Me is where you look back, not where you check your balance.

Then:

### 3.1 This week, in three numbers

Average sleep, average steps, and the happenings that came up most often. Three
entities, three readings. No radar, no rings.

Most-frequent happenings come straight from the `useCount` / `lastUsedAt` fields
introduced by the happenings rework — no new aggregation needed.

### 3.2 Connected apps

Each connected app, with the colors it cost this week. Source:
`appStepsSpentByDay`, which already holds exact per-app spend keyed by day.

**Colors, not minutes — and this is not a simplification, it is a correctness
fix.**

Real per-app screen time is not readable by an app. iOS exposes it only through
`DeviceActivityReport`, a view rendered by a separate extension in another
process, whose numbers cannot be pulled into the app's model. No such extension
exists in this project.

The current `topAppsSection` does render minutes, but look where they come from
(`MeView.swift:885`):

```swift
case "minutes10": resolved = 10
case "minutes30": resolved = 30
```

Those are minutes **bought**, read out of the payment log — not minutes used.
Buy a 30-minute window, spend three, and the chart still counts 30. Since a
window is consumed by actual usage and is routinely left unfinished, the existing
number overstates systematically. Replace it; do not port it.

### 3.3 The calendar

Past days, scrolling horizontally back into the past. Tapping a day opens that
day's canvas as a poster.

**Most of this already exists — reuse it, do not rebuild it.** `HistoryView`
renders past days grouped by month and opens `DayCanvasViewerView`, described in
its own source as a pixel-faithful render of the persisted canvas. The work is
re-laying it out as a horizontal scroll and hosting it inside Me.

**The Pro gate must survive the move.** Today the newest
`SubscriptionGate.freeHistoryDayCount` days are always unlocked and older ones
are blurred behind a Pro badge; Pro users get unbounded history. It is easy to
lose this in a re-layout and quietly hand every free user their whole archive.
`HistoryView` also has a `debugForceUnlock` path — keep it debug-only.

---

## 4. Tabs: five to three

| Today | After |
|-------|-------|
| 0 Canvas | 0 Canvas |
| 1 Feeds | 1 Feeds |
| 2 Me | 2 Me |
| 3 History | folded into Me as the calendar |
| 4 Settings | button, top right of Me |

Nothing is lost. Notes are unaffected — `ManualsPage` is reached from inside
`SettingsSheet` (`SettingsSheet.swift:85`), not from a tab, despite what
`README.md` says. Correct the README as part of this work; it also still
describes a five-tab structure.

The tab bar iterates `Tab.allCases`, so removing the enum cases updates it
automatically. Two things do not update themselves:

**`@SceneStorage("selectedTab")` persists across launches.** A user whose last
session ended on Settings has `4` stored. After the collapse that resolves to
nothing. **Clamp out-of-range stored values to `.canvas` on read.** Without this,
part of the beta cohort opens the first build after update onto a blank screen.

**The feature-tip deep link** in `MainTabView` switches to the Settings *tab* and
pushes a route (`onReceive(.openFeatureTipSettings)`, around line 179). It must
now present the settings sheet and push the route inside it.

---

## 5. What is removed

| From Me | Why |
|---------|-----|
| Radar chart and axes | Built on body / mind / heart, deleted by the happenings rework |
| `RadarLayout`, `RadarCenterKey`, `radarBackground`, `radarTapOverlay` | Radar layout mathematics |
| `radarSnaps`, `radarSummary`, `radarAxes` state | Same |
| `MeAxisDetailView` | Opens a dimension that no longer exists |
| Weekly rings | Replaced by the three-number summary |
| Reflection block | Not one of the four things worth knowing |
| `topAppsSection` minutes bars | Replaced by exact color spend |

Re-examine `MeViewSupport.swift` once the radar is gone — `MeWeekSummary` in
particular is shaped around the old breakdown. `MeLifecycleModifier` and
`MeSheetsModifier` should survive but will shrink.

---

## 6. Principal files

| File | Role |
|------|------|
| `StepsTrader/Views/MeView.swift` (908 lines) | The screen. Loses the radar and most of its length |
| `StepsTrader/Views/MeViewSupport.swift` | Supporting types; revisit after the radar goes |
| `StepsTrader/Views/MeAxisDetailView.swift` | Delete |
| `StepsTrader/Views/HistoryView.swift` | Becomes the calendar inside Me; keep the Pro gate |
| `StepsTrader/Views/DayCanvasViewerView.swift` | The poster preview. Unchanged |
| `StepsTrader/Views/MainTabView.swift` (591 lines) | Tab enum, tab bar, `StepBalanceCard` overlay, feature-tip deep link |
| `StepsTrader/Views/SettingsSheet.swift` | Presented as a sheet; `embeddedInTab` defaults to false |
| `StepsTrader/Stores/UserEconomyStore.swift` | `appStepsSpentByDay` — source for the apps block |
| `README.md` | Corrections: three tabs, no Notes tab |

---

## 7. Acceptance criteria

- [ ] The tab bar has exactly three destinations
- [ ] **A stored `selectedTab` of `3` or `4` from a previous version opens the canvas** — verify by setting it before launch, not by reasoning about it
- [ ] `StepBalanceCard` appears on canvas and feeds, and not on me
- [ ] Settings opens from a button at the top right of Me
- [ ] Everything previously reachable from the Settings tab is still reachable, including `ManualsPage`
- [ ] The feature-tip deep link still lands on its settings page
- [ ] Me shows average sleep, average steps, and the week's most frequent happenings
- [ ] The apps block shows exact color spend per app from `appStepsSpentByDay`
- [ ] No screen reports minutes spent per app
- [ ] The calendar scrolls horizontally into the past and opens a day's poster on tap
- [ ] **A free account sees exactly the same number of unlocked days as before the move**, and older days stay blurred behind the Pro badge
- [ ] `README.md` describes three tabs and does not mention a Notes tab

---

## 8. Working agreement

- Do this after the happenings rework, not beside it.
- Reuse `HistoryView` and `DayCanvasViewerView`. The poster rendering is
  pixel-faithful to persisted data and is not worth re-deriving.
- The two gates in this work — the `selectedTab` clamp and the history Pro
  limit — both fail silently and both affect existing users. Test them
  deliberately rather than assuming.
- Report honestly. If removing the radar turns out to unpick more of
  `MeViewSupport` than this brief assumes, say so rather than expanding scope
  quietly.
