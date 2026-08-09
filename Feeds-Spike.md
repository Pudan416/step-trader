# Spike — can the DeviceActivityMonitor extension update a Live Activity?

**Date:** 2026-08-09
**Branch:** `spike/feeds-live-activity` (from `main`)
**Answers:** `Feeds-Spec.md` § "Unresolved: can the monitor extension update the Live
Activity?" and the first spike checkbox in `Feeds-Brief.md` §6.

---

## The question

`Feeds-Spec.md` blocks the timer on one yes/no: **does `Activity.update` work from
inside a `DeviceActivityMonitor` extension?**

It matters because of how the window is measured. Per-minute
`usageBudgetTick_<groupId>_<m>` events arrive in the extension while the user is
inside Instagram and Nowhere is not running. If the extension cannot reach
ActivityKit, nothing can keep the Live Activity honest, and §6's fallback applies:
show the window's size with a `staleDate` and refresh only when the app next runs.

The documented failure mode is specific — `Activity.activities` arriving empty
inside an extension — so the harness distinguishes **three** outcomes, not two:

1. the extension sees the activity and `update` succeeds;
2. it sees the activity and `update` throws;
3. it does not see the activity at all.

(3) means the process is not handed the list, and it is fixed differently from (2).
Collapsing them into a single "no" would throw away the distinction that decides
whether a workaround exists.

## Scope

**In:** the smallest thing that produces the answer, and a runbook for producing it.

**Out:** the flat list, the unlock sheet, the timer screen, the production
`ActivityAttributes` shape, `excessiveActivities` handling.

**Also out — and deliberately so:** the second spike checkbox, about
`NSSupportsLiveActivitiesFrequentUpdates` and throttling late in a long window.
That needs a real 60-minute window and is a separate run once this question is
answered. The plist key is set here, but nothing in this harness tests it.

---

## Design

### Shared attributes type

`Shared/SpikeLiveActivityAttributes.swift`, added to the Steps4, DeviceActivityMonitor
and UnlockWidgetExtension targets — the same arrangement `DayBoundary.swift` and
`ShieldRebuildHelper.swift` already use. No new sharing mechanism.

`ContentState` carries `remainingMinutes`, `updateCount`, and `lastUpdatedBy`, whose
value is one of `app`, `monitor:intervalDidStart`, `monitor:eventDidReachThreshold`.
`lastUpdatedBy` *is* the answer: if the Lock Screen reads `monitor:…`, the extension
reached ActivityKit.

### Live Activity view

A plain three-line view in `UnlockWidget/`, registered in `UnlockWidgetBundle`.
Deliberately ugly — it is a lamp, not the Feeds timer, and it will be deleted or
rewritten regardless of the answer.

`Steps4/Info.plist` gains `NSSupportsLiveActivities` and
`NSSupportsLiveActivitiesFrequentUpdates`. Both are required by `Feeds-Brief.md` §7
anyway.

### Trigger

One button in the existing DEBUG section of `SettingsSheet.swift`, beside the
shield-diagnostics rows. It starts the Live Activity in the foreground — the only
place ActivityKit permits starting one — stores its `id` in app-group defaults, and
registers two DeviceActivity activities.

**Two activities, not one**, so a failure in either cannot mask the other:

| Name | Schedule | Events | Triggers |
|------|----------|--------|----------|
| `spikeProbe` | now+2min → now+20min, no repeat | none | `intervalDidStart`, with zero app usage |
| `spikeUsage` | 0:00:00 → 23:59:59, repeating | one, `threshold: DateComponents(minute: 1)` | `eventDidReachThreshold`, after one real minute |

`spikeProbe` answers in about three minutes and needs nobody to look at a phone.
`spikeUsage` is the production path exactly.

The two are the same process under the same entitlement, so a yes on `spikeProbe`
makes a yes on `spikeUsage` very likely — but "very likely" is not the bar the spec
sets, which is why both are in the build.

### Extension side

`intervalDidStart(for: "spikeProbe")` and
`eventDidReachThreshold("spikeUsageTick")` both call `runSpikeProbe(trigger:)`, which
records, in order:

1. `Activity<SpikeLiveActivityAttributes>.activities.count` — outcome (3) above;
2. whether the stored `id` is among them;
3. the result of `update`, with any thrown error verbatim;
4. elapsed time.

Everything goes through the extension's existing `appendMonitorLog` into
`SharedKeys.monitorLogs`, which `BlockingStore.dumpShieldDiagnostics()` already dumps
behind a copy button (`StepsTrader/Stores/BlockingStore.swift:441`). No new UI.

---

## Two things that could produce a false answer

**`Activity.update` is async; the monitor callbacks are not.** The extension process
is torn down shortly after a callback returns, so an unbounded `await` may simply
never land. The probe bounds the wait with an explicit timeout and logs the elapsed
time. A timeout is recorded as a timeout, never as a refusal — those are different
answers and only one of them has a workaround.

**`spikeProbe`'s schedule breaks near midnight.** `DateComponents` here are
time-of-day, so "now +20 minutes" wraps past 23:59, and `Feeds-Spec.md` already
records what DeviceActivity does with `end < start`: it treats the interval as
already ended and kills the monitor before anything fires. The button checks for this
and says so, rather than starting a probe that silently cannot report.

---

## Runbook

Both runs need a physical device with Screen Time authorization already granted.
Neither works in the simulator.

**Run A — schedule path, ~3 minutes, no app usage.**

1. Nowhere → DEBUG settings → the spike button.
2. Confirm the Live Activity appears, reading `app`.
3. Lock the phone and leave it for three minutes.
4. Look at the Lock Screen. Did `lastUpdatedBy` change to `monitor:intervalDidStart`?

**Run B — production path, ~2 minutes of real usage.**

1. Tap the spike button again.
2. Open one of the apps in the group and stay in it for a full minute — the threshold
   counts screen time, so putting the phone down pauses it.
3. Check the Dynamic Island or Lock Screen for `monitor:eventDidReachThreshold`.

**Either way:** back in Nowhere, copy the shield diagnostics and hand them over. The
log lines carry the parts the Lock Screen cannot show — the activities count and the
verbatim error.

## Recording the result

The answer goes into `Feeds-Spec.md` under "Unresolved", as both documents require.
If it is no, `Feeds-Spec.md` must be updated to the `staleDate` fallback **before**
any timer implementation starts, and `Feeds-Brief.md` §9 applies: report it and stop,
rather than shipping a wall-clock timer that looks right in a screenshot.

## Disposal

If the answer is no, the branch is deleted whole. If yes, the attributes type and the
Live Activity views carry into the Feeds implementation as a tested foundation; the
DEBUG button and both spike activities do not.
