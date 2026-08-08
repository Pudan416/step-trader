# Implementation brief — feeds

Self-contained brief for reworking Nowhere's Feeds tab. Written to be handed to
an implementer cold. Design rationale lives in `Feeds-Spec.md`; this is the
execution surface.

Read `Happenings-Brief.md` §1 for shared project context and the build command.
The two reworks are independent and can proceed in either order.

---

## 1. The problem

Feeds is built on a paper-ticket metaphor. Apps are gathered into groups, each
group renders as a ticket with a sticker theme, and unlocking runs through a
ticket's settings. To open Instagram you navigate a stack of tickets instead of
tapping Instagram.

The metaphor is charming and it is in the way.

---

## 2. Target behaviour

**One scrolling list.** Each app appears as its own icon with its name. Anything
currently blocked carries a lock badge.

**Tap a locked app** → a sheet offering three windows: 10, 30 and 60 minutes at
4, 10 and 20 colors. Both intervals and prices are unchanged. The sheet should
read like the PayGate — warm, deliberate — but it is Nowhere's own screen, not
the system shield.

**Buy a window** → the timer screen. A radial arc that depletes as the window is
spent, remaining time in large monospaced digits, and beneath it the list of apps
this window covers. Tapping one launches it.

Night theme throughout. The supplied reference image for the timer is light —
it was provided to show how time is *displayed* (depleting arc, large mono
digits), not as a color direction. Do not build a light screen.

---

## 3. Assumption that needs confirming first

The spec says apps appear individually; the underlying model unlocks by
**group**. These have to be reconciled.

**Working assumption:** the list flattens apps out of their groups for display.
Tapping an app opens the unlock sheet, and buying a window activates the monitor
for the group that app belongs to. The sheet states plainly which other apps the
window also opens.

The alternative — each app becoming its own group — reads more naturally from
the list, and it is the reading the design implies. It has two costs. Every
concurrently open window is another `DeviceActivityCenter` activity against the
cap of twenty, which a per-app model reaches far sooner than a per-group one.
And `SubscriptionGate.freeMaxBlockingGroups` is 2, so a per-app model would
paywall at the third app *if the paywall were ever switched back on*.

It is not on today: `SubscriptionGate.allFeaturesUnlocked` is `true`, which makes
`isPro` unconditionally true and every gate dormant. The app ships free. The
constants remain as a kill-switch — the file documents flipping it back — so a
per-app model is a decision that quietly reprices the product should that happen.
Not a blocker, but worth knowing before choosing.

**Confirm the reading before building the list.**

---

## 4. Three platform constraints

These are not implementation details. Each one bounds the design, and each one
looks solvable until you try.

### App icons cannot be extracted

`FamilyActivitySelection` yields opaque `ApplicationToken` values. There is no
API to read an app's name or icon from one — Apple closed this deliberately so
apps cannot enumerate what is installed. The only way to render a real icon is
the FamilyControls-provided SwiftUI `Label(token)`, drawn by the system in its
own process. It cannot be recolored, masked, or placed in a custom shape.

`TargetResolver` already works around this with a registry of known apps, each
carrying a bundled asset. Its API: `imageName(for:)`, `displayName(for:)`,
`primaryAndFallbackSchemes(for:)`.

**Decision:** registry apps use our assets with full styling control. Everything
else renders as an unstyled system `Label`. The list looks visually mixed and
that is accepted.

Note what exists today: `PaperTicketView` only resolves an icon when a group has
a `templateApp`, and otherwise falls back to `Image(systemName: "app.fill")`. It
never uses `Label(token)` at all. Introducing it is new work, and it is the only
way non-registry apps get a real icon.

### Nothing can draw over another app

While the user is inside Instagram, Nowhere cannot render on top. The only
surface visible from another app is a Live Activity. See §6.

### DeviceActivity is capped at twenty activities

Documented ceiling for an app and its extensions combined; beyond it
`startMonitoring` throws
`DeviceActivityCenter.MonitoringError.excessiveActivities`. Neighbouring limits:
a selection holds at most **50 application tokens**, and a schedule's interval
cannot be shorter than **15 minutes**.

The ceiling counts concurrently monitored windows, not rows in the list. Current
code catches the throw and stops the monitor but tells the user nothing. Add a
user-facing error — silent failure here means an app the user paid to block
stays open.

---

## 5. The window is spent, not elapsed

**Read this before writing any timer code.** It is easy to miss because the code
reads like a schedule.

The `DeviceActivitySchedule` spans `0:00:00`–`23:59:59`. It exists only to
satisfy the framework's 15-minute minimum. The real window is measured by
`DeviceActivityEvent` thresholds in **minutes of app usage**:

```swift
threshold: DateComponents(minute: m)
```

"10 minutes" means ten minutes of actually looking at the app. Put the phone
down and the window stops draining. This is deliberate and it stays.

Two consequences:

**A wall-clock countdown would be a lie.** Digits melting while the phone lies
face-down misreport what the user has left.

**The real signal arrives once a minute.** `usageBudgetTick_<groupId>_<m>` events
already fire per minute of usage — see `AppModel+PayGate.swift:162`. The honest
indicator steps a minute at a time. It does not flow.

**Do not interpolate between ticks to make the arc smooth.** It would run ahead
of the truth and then jump backwards when the next tick lands. A stepping arc
that is correct beats a flowing arc that is not.

A 60-minute window currently registers ~64 events (59 per-minute ticks, up to
four widget milestones, one completion). The documented cap is on activities,
not events, so this is legal — but it is heavy.

---

## 6. Live Activity

New infrastructure. ActivityKit appears nowhere in the project today;
`UnlockWidget` is a plain WidgetKit extension with a timeline provider, which is
a different mechanism.

Required:

- `NSSupportsLiveActivities` in `Steps4/Info.plist`
- An `ActivityAttributes` type carrying the entry's name, icon identity, and
  remaining usage minutes
- Live Activity views added to the existing widget extension
- Start on unlock, from the app, in the PayGate flow. Live Activities may only be
  *started* while the app is in the foreground — the unlock flow satisfies this
- End on expiry and on early close

**Do not use `Text(timerInterval:countsDown:)`.** It is the usual answer for Live
Activity countdowns and it is wrong here: it counts wall-clock time, and this
window is spent by usage.

### Spike this before building the timer

Ticks arrive in the `DeviceActivityMonitor` extension. The app is not running
then — the user is inside Instagram. So the update must come from the extension.

**Whether `Activity.update` works from a `DeviceActivityMonitor` extension is not
established.** Apple documents background updates but not this extension
specifically, and there are developer reports of `Activity.activities` arriving
empty inside a widget extension, fixed by moving the update into the app — which
is not available here.

Settle it with a spike on a physical device. It is a yes/no that decides the
shape of the feature and cannot be answered by reading.

**If the answer is no:** the Live Activity shows the window's size with a
`staleDate`, refreshing only when the app next runs. Degraded but honest. Do not
ship a Live Activity that displays a stale number as if it were live.

Frequency is a second risk: iOS throttles frequent updates against an
undocumented budget, and sixty updates across an hour is within reach of it. Set
`NSSupportsLiveActivitiesFrequentUpdates` and confirm updates still land in the
final minutes of a long window.

Deployment target is iOS 18, above ActivityKit's 16.1 requirement.

---

## 7. Principal files

| File | Role |
|------|------|
| `StepsTrader/Views/AppsPageSimplified.swift` (452 lines) | The ticket stack. Becomes the flat list |
| `StepsTrader/Views/Components/PaperTicketView.swift` | Current row rendering, incl. the `app.fill` fallback. Replaced |
| `StepsTrader/Views/PayGateView.swift` | Existing unlock UI. The new sheet reuses its flow, restyled |
| `StepsTrader/AppModel+PayGate.swift` | Monitor lifecycle. Gains Live Activity start/stop and `excessiveActivities` handling |
| `StepsTrader/TargetResolver.swift` | Assets for the list, schemes for launching from the timer |
| `StepsTrader/Stores/SubscriptionGate.swift` | `freeMaxBlockingGroups = 2`. Must not tighten |
| `StepsTrader/Models/TicketGroup.swift` | Unchanged |
| `UnlockWidget/` | Gains the Live Activity views |
| `Steps4/Info.plist` | Gains `NSSupportsLiveActivities` |

Unchanged and deliberately so: `AccessWindow` keeps `minutes10` / `minutes30` /
`hour1`, costs stay 4 / 10 / 20. No enum migration, no repricing. The shield
extensions are untouched — this changes how a window is bought and displayed,
not how blocking works.

---

## 8. Acceptance criteria

- [ ] Feeds is a single scrolling list; no ticket stack remains
- [ ] A registry app shows its bundled asset; a non-registry app shows a system `Label`
- [ ] Locked entries carry a lock badge
- [ ] Tapping a locked entry offers 10 / 30 / 60 minutes at 4 / 10 / 20 colors
- [ ] The sheet names the other apps a window will also open
- [ ] A free user can still reach exactly the same set of apps as before this change
- [ ] Buying a window opens the timer screen, in the night theme
- [ ] The timer lists the window's apps, and tapping one launches it
- [ ] **The timer does not move while the covered apps are unused** — verified by
      leaving the phone idle with a window open and confirming nothing drains
- [ ] The arc steps on tick boundaries and never runs backwards
- [ ] A Live Activity appears on unlock and shows remaining time in the Dynamic Island
- [ ] The Live Activity ends on expiry and on early close
- [ ] Exceeding the DeviceActivity cap surfaces a user-facing error rather than
      leaving an app silently unblocked

### Spikes, before the timer is built

- [ ] On a physical device: does `Activity.update` succeed from inside the
      `DeviceActivityMonitor` extension? Record the answer in `Feeds-Spec.md`.
      If no, the fallback in §6 applies and the spec must be updated before
      implementation starts
- [ ] Confirm per-minute updates still land in the final minutes of a 60-minute
      window with `NSSupportsLiveActivitiesFrequentUpdates` set

---

## 9. Working agreement

- FamilyControls and DeviceActivity need a physical device. The list and sheet
  can be built in the simulator; the timer, the monitor and the Live Activity
  cannot be trusted there.
- §3 is an assumption, not a decision. Confirm it before building the list.
- Report honestly. If the spike in §6 comes back negative, say so and stop —
  do not quietly ship a wall-clock timer because it looks right in a screenshot.
