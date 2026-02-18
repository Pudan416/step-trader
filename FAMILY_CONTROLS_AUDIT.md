# Family Controls System Audit

**Date:** 2026-02-17  
**Scope:** Full review of FamilyControls, DeviceActivity, ManagedSettings, and all related app/extension code.

---

## Architecture Overview

```
Main App                          Extension (separate process)
┌──────────────────────┐          ┌──────────────────────────────┐
│ AppModel              │          │ DeviceActivityMonitorExtension│
│  ├─ BlockingStore     │──writes──│  ├─ intervalDidStart()       │
│  │   └─ applyShield() │  shared  │  ├─ eventDidReachThreshold() │
│  ├─ FamilyControlsSvc │  UDefs   │  ├─ rebuildBlockFromExtension│
│  │   └─ startMonitor()│─────────>│  └─ applyMinuteCharge()     │
│  ├─ AppModel+PayGate  │          └──────────────────────────────┘
│  ├─ AppModel+Payment  │
│  └─ AppModel+Budget   │
└──────────────────────┘
```

Both processes read/write to the same App Group `UserDefaults` with **no coordination mechanism**.

---

## Critical Issues

### 1. Ticket groups have NO minute-mode event registration

**Files:** `FamilyControlsService.swift:83-114`, `DeviceActivityMonitorExtension.swift:572-629`

Both `buildMinuteEvents()` (main app) and `buildAllMinuteEvents()` (extension) exclusively read from the legacy `appUnlockSettings_v1` dictionary. Neither reads the new `TicketGroup`-based system. This means:

- Shields are correctly applied for ticket groups (via `BlockingStore`)
- **But no per-minute charge events ever fire** for ticket group apps
- Minute tariff billing only works for legacy per-app configurations
- This is the single biggest functional gap in the system

### 2. Day key mismatch between app and extension

**Files:** `DayBoundary.swift`, `DeviceActivityMonitorExtension.swift:805-810`, `AppModel+Payment.swift`

The extension computes `dayKey` with a plain `yyyy-MM-dd` DateFormatter. The main app uses `DayBoundary.dayKey()` which respects custom `dayEndHour`/`dayEndMinute`. If the user sets "day ends at 3 AM":

- Extension logs charges under calendar date (e.g., `2026-02-18` after midnight)
- App considers it still `2026-02-17` until 3 AM
- Per-day spent tracking is split across two "days"
- `stepsBalanceAnchor` comparison can trigger a false day-reset, **erasing legitimate charges**

### 3. `stepsBalanceAnchor` written differently by app vs extension

**Files:** `DeviceActivityMonitorExtension.swift:739`, `AppModel+Payment.swift:106`

- Extension sets anchor to `Calendar.current.startOfDay(for: Date())` (midnight)
- App sets anchor to `currentDayStart(for: Date())` (respects custom day boundary)
- When the app reads the extension's anchor after midnight but before the custom day-end, it sees a "different day" and resets `spentStepsToday` to 0
- **Result:** User gets free EXP; extension charges are silently erased

### 4. No coordination on shared UserDefaults writes (race condition)

**Files:** `AppModel+Payment.swift`, `AppModel+DailyEnergy.swift`, `DeviceActivityMonitorExtension.swift`

Both the main app and extension read-then-write `stepsBalance`, `spentStepsToday`, and `debugStepsBonus_v1` with no locking, file coordination, or compare-and-swap. Concurrent writes (user opens app while extension fires minute event) can cause:

- Lost charges (extension write overwritten by app recalculation)
- Double-charges (both deduct independently from stale reads)
- Balance going negative without proper handling

### 5. Extension `intervalDidStart` ignores unlock timestamps

**Files:** `DeviceActivityMonitorExtension.swift:345`

`setupBlockForMinuteMode()` filters groups by `group.active` only and **never checks `groupUnlock_*` keys**. Meanwhile `rebuildBlockFromExtension()` correctly checks unlock dates. This means:

- Every time the daily monitoring interval starts (midnight), **all active groups are blocked regardless of active unlocks**
- Users who paid to unlock apps will find them re-blocked at midnight even if their unlock window hasn't expired

### 6. Extension spent steps are invisible to the app

**Files:** `DeviceActivityMonitorExtension.swift:745`, `UserEconomyStore`

The extension writes spent steps to `appStepsSpentToday_v1` in UserDefaults. The main app's `loadAppStepsSpentToday()` reads from a JSON file via `PersistenceManager`. Extension-tracked spending is invisible to the app until a full restart triggers a migration path. The UI shows an inaccurate balance.

### 7. Day pass not checked by extension before minute charges

**Files:** `AppModel+Payment.swift`, `DeviceActivityMonitorExtension.swift`

Day pass grants are stored under `"appDayPassGrants_v1"` in UserDefaults. The extension's `applyMinuteCharge()` never checks for day passes before deducting balance. A user who buys a day pass still gets charged per-minute by the extension until monitoring is manually restarted.

---

## High Severity Issues

### 8. Shield rebuild race condition (dual debounce paths)

**File:** `BlockingStore.swift:134, 234`

`persistTicketGroups()` and `rebuildFamilyControlsShield()` both cancel the shared `rebuildBlockTask` but use different debounce timings (500ms vs 50ms). If `persistTicketGroups()` fires then `rebuildFamilyControlsShield()` is called within 500ms, the persist task's rebuild is cancelled and never executes. The shield can remain in a stale state.

### 9. Dual shield application from app and extension

**Files:** `BlockingStore.swift:298`, `DeviceActivityMonitorExtension.swift:345, 259`

Both `BlockingStore.applyShieldImmediately()` and the extension's `setupBlockForMinuteMode()`/`rebuildBlockFromExtension()` write to the same `ManagedSettingsStore(named: "shield")`. They use **different filtering logic** (app checks unlock timestamps; extension's `intervalDidStart` doesn't). They can overwrite each other's state unpredictably.

### 10. Schedule gap at midnight

**Files:** `FamilyControlsService.swift:54-58`, `DeviceActivityMonitorExtension.swift:553-557`

The `DeviceActivitySchedule` runs from `00:00` to `23:59`. There's a 1-minute gap from 23:59 to 00:00 where no monitoring occurs. Any app usage in that window won't trigger events.

### 11. `scheduleUnlockExpiryActivity` midnight-crossing bug

**File:** `AppModel+PayGate.swift:159-191`

For long unlocks (>= 900s), `DateComponents` are built from `.hour, .minute, .second`. If start is `23:50:00` and end is `00:50:00` (crosses midnight), the interval end is interpreted as earlier in the same day. The schedule may never fire or fire immediately, leaving apps unlocked indefinitely.

### 12. Double-counting in `simulateAppUsage()`

**File:** `AppModel+BudgetTracking.swift:344-365`

`simulateAppUsage()` calls `updateSpentTime(minutes: spentMinutes + 1)` then `consumeMinutes(1)`, which internally calls `updateSpentTime` again. Each simulated minute increments `spentMinutes` by **2** instead of 1. Budget is consumed at double speed in the timer fallback mode.

> Note: `minuteModeEnabled` is currently hardcoded to `false`, so this and minute tariff code is effectively dead. But if re-enabled, this bug activates.

### 13. `TicketGroup.cost(for:)` ignores `settings.entryCostSteps`

**File:** `TicketGroup.swift:27`

Returns hardcoded flat costs (4/10/20 for 10min/30min/1hr) regardless of `settings.entryCostSteps` or `settings.dayPassCostSteps`. Per-group cost customization is stored but never used.

### 14. `TicketGroup.init` overwrites `enabledIntervals`

**File:** `TicketGroup.swift:21`

The initializer ignores any `enabledIntervals` parameter and always hardcodes `[.minutes10, .minutes30, .hour1]`. Custom interval subsets are impossible.

---

## Medium Severity Issues

### 15. No `authorizationStatus` change observation

**File:** `FamilyControlsService.swift`

If the user revokes Family Controls authorization in Settings.app, `isAuthorized` stays `true` until app restart. No `NotificationCenter` observer for `AuthorizationCenter.authorizationStatusDidChange`.

### 16. `stopTracking()` methods are disconnected

**Files:** `AppModel+BudgetTracking.swift:283`, `BlockingStore.swift:352`

`AppModel.stopTracking()` stops DeviceActivity monitoring but doesn't clear the `ManagedSettingsStore`. `BlockingStore.stopTracking()` clears the store but isn't called from `AppModel`. Stopping tracking from the app leaves shields potentially active.

### 17. `BlockingStore.stopTracking()` clears ALL ManagedSettings

**File:** `BlockingStore.swift:352-362`

`ManagedSettingsStore.clearAllSettings()` wipes the entire named store, not just the shield. If any other managed settings (web content, media restrictions) were on the same store, they'd be cleared too. Should use targeted `store.shield.applications = nil` instead.

### 18. `applyMinuteTariffCatchup` key restoration bug

**File:** `AppModel+BudgetTracking.swift:308-341`

When balance runs out, the function calls `removeObject` for session keys, then writes `Date()` to `minuteTariffLastTickKey` on a later line, **restoring the key that was just deleted**. Could cause phantom minute charges to restart.

### 19. `NSKeyedArchiver`-based token keys are fragile

**Files:** `BlockingStore.swift:18`, `ShieldGroupSettingsView.swift`, `AppModel+TicketGroups.swift:65`

`ApplicationToken` is archived to `Data`, base64-encoded, and used as a UserDefaults key. The serialized form may change between OS versions, silently breaking all existing unlock timestamps and bundle ID mappings.

### 20. Legacy `handlePayGatePayment` uses flat cost for all windows

**File:** `AppModel+PayGate.swift:255-290`

The per-bundleId legacy path uses `entryCostSteps` as the cost regardless of the `AccessWindow` selected. A 10-minute and 1-hour unlock cost the same, unlike the group-based path which correctly uses `group.cost(for: window)`.

### 21. `appUnlockSettings` and ticket groups can overlap

**File:** `BlockingStore.swift:281-292`

Both data models can contain the same app tokens. Unlock logic differs between the two paths (ticket groups use `groupUnlock_` keys; legacy uses `blockUntil_` keys). An app could be "unlocked" via one path but re-blocked by the other.

### 22. Inconsistent key usage (hardcoded vs SharedKeys)

**Files:** `HandoffManager.swift`, `AppModel+DailyEnergy.swift`, `DeviceActivityMonitorExtension.swift`

Many files use raw string literals for UserDefaults keys instead of `SharedKeys` constants. The extension doesn't even have access to `SharedKeys` (separate target). If a key name changes in one place, the other side silently breaks.

### 23. Duplicate UserDefaults accessors

**Files:** `SharedKeys.swift`, `UserDefaults+StepsTrader.swift`

`SharedKeys.appGroupDefaults()` and `UserDefaults.stepsTrader()` both return the same App Group UserDefaults through different code paths. Maintenance risk and cognitive overhead.

### 24. Silent fallback to `UserDefaults.standard`

**File:** `UserDefaults+StepsTrader.swift`

If the App Group container is unavailable (entitlements misconfiguration, first launch), the method falls back to `.standard`. The main app writes to `.standard` while the extension reads from the App Group suite -- data never reaches the extension. Error is logged once and silently ignored.

### 25. Extension `DateFormatter` allocation on every call

**Files:** `DeviceActivityMonitorExtension.swift:805-810, 89`

`dayKey(for:)` and `appendMonitorLog` create new formatters on every invocation. In an extension with ~6MB memory limit, this is wasteful. `handleMinuteEvent` calls `dayKey` every minute per tracked app. Should use static cached formatters.

### 26. Category tokens not filterable for per-app unlocks

**File:** `BlockingStore.swift:264-276`

Individual `applicationTokens` are checked against unlock keys, but `categoryTokens` are always added unfiltered. There's no mechanism to unlock a single app within a category -- the entire category stays blocked.

### 27. Quick unlock side-effect inside cancellable editor

**File:** `ShieldGroupSettingsView.swift`

The "quick unlock" button calls `model.handlePayGatePaymentForGroup()` (a non-reversible side-effect) then dismisses. If the view is modeled as a Cancel/Save editor, the unlock persists even if the user conceptually "cancelled." The payment is a one-way action inside a two-way UI.

### 28. No notification on minute-mode depletion

**File:** `DeviceActivityMonitorExtension.swift:521`

When `remainingMinutes <= 0`, the extension sets `minuteModeDepleted_v1 = true` and stops monitoring. No local notification is sent. The user has no idea why monitoring stopped or that their balance hit zero.

---

## Low Severity Issues

### 29. Unused `currentDayKey()` in `FamilyControlsService`

**File:** `FamilyControlsService.swift:116-118`  
Dead code.

### 30. Redundant `Task` in `updateMinuteModeMonitoring()`

**File:** `FamilyControlsService.swift:47`  
Already on `@MainActor`; the inner `Task { @MainActor in }` is redundant and introduces ordering issues on rapid calls.

### 31. Silent decode failure in `buildMinuteEvents()`

**File:** `FamilyControlsService.swift:86`  
If `appUnlockSettings_v1` is corrupted, `try?` returns empty events with no logging.

### 32. `applyFamilyControlsSelection(for:)` ignores its parameter

**File:** `AppModel+TicketManagement.swift:20`  
Accepts a `bundleId` parameter but does a full rebuild regardless. Misleading API.

### 33. Double `onDismiss` in settings sheet

**File:** `AppsPageSimplified.swift`  
Both "Done" button and `.onDisappear` call `onDismiss`. Harmless but unnecessary.

### 34. Sheet dismiss/present race condition

**File:** `AppsPageSimplified.swift`  
"Edit Apps" dismisses settings sheet and immediately presents picker. Can trigger "presenting while dismissing" warnings on some OS versions.

### 35. Phantom empty groups can accumulate

**File:** `AppsPageSimplified.swift`  
Groups with no apps are hidden from the list. Combined with deletion-on-picker-dismiss logic, phantom groups can accumulate if the cleanup path isn't triggered (e.g., app killed between creation and picker dismiss).

### 36. `ForEach` keyed by `\.offset` for tokens

**File:** `ShieldRowView.swift`  
Tokens are `Hashable` but keyed by position index. SwiftUI can't animate individual token additions/removals correctly.

### 37. No accessibility labels on ticket rows

**File:** `ShieldRowView.swift`  
The entire row is a button with no `.accessibilityLabel`. VoiceOver users get no context.

### 38. `NavigationView` usage (deprecated)

**Files:** `ShieldGroupSettingsView.swift`, `CategorySettingsView.swift`  
Should use `NavigationStack` (iOS 16+).

### 39. `Tariff.stepsPerMinute` for `.free` returns 100

**File:** `Types.swift:107`  
Comment says "avoid divide-by-zero" but returning 100 for a free tariff can confuse budget calculations and UI.

### 40. Static `AppModel.minuteModeEnabled` doesn't trigger SwiftUI updates

**File:** `ShieldRowView.swift`  
`isActive` references `AppModel.minuteModeEnabled` which is static. Changes won't cause reactive UI updates.

### 41. TargetResolver only supports 11 hardcoded apps

**File:** `TargetResolver.swift`  
Any app not in the list returns empty schemes, making handoff impossible. No user-configurable URL scheme support.

### 42. HandoffManager only tries first URL scheme

**File:** `HandoffManager.swift`  
`bundleScheme(for:)` uses `schemes.first` with no fallback, unlike `AppModel.attemptOpen()` which iterates through alternatives.

### 43. Duplicate `sendTimeExpiredNotification` methods

**File:** `NotificationManager.swift:17-59`  
Two near-identical overloads; the one accepting `remainingMinutes` ignores the parameter.

### 44. `@AppStorage` vs `UserDefaults.stepsTrader()` mismatch

**File:** `CategorySettingsView.swift`  
`@AppStorage("userStepsTarget")` reads/writes `.standard` but `loadSettings()`/`saveSettings()` use `.stepsTrader()`. Slider value and saved value diverge.

### 45. `UserDefaults.standard` usage for option entries

**File:** `CategoryDetailView.swift`  
Entry persistence uses `.standard` instead of `.stepsTrader()`. Data won't be accessible from extensions.

---

## Recommended Priority Fixes

### P0 (Do First)
1. ~~**Fix ticket group minute-mode events** (#1)~~ -- MOOT: minute mode disabled/dead code
2. ~~**Unify day key logic** (#2, #3)~~ -- FIXED: extension now uses custom day boundary from SharedKeys
3. **Add coordination for shared UserDefaults** (#4) -- use `NSFileCoordinator` or atomic read-modify-write patterns (DEFERRED: needs architectural decision)
4. ~~**Check unlock timestamps in `setupBlockForMinuteMode`** (#5)~~ -- FIXED: now checks `groupUnlock_` keys

### P1 (High Impact)
5. ~~Fix midnight-crossing bug in `scheduleUnlockExpiryActivity` (#11)~~ -- FIXED: unified warningTime approach
6. Bridge extension spent steps to main app (#6) -- DEFERRED: requires shared file or UserDefaults key alignment
7. ~~Check day passes in extension before charging (#7)~~ -- MOOT: minute charging disabled
8. Fix the dual shield application inconsistency (#9) -- PARTIALLY FIXED via #5 (both paths now check unlocks)
9. ~~Close the 23:59-00:00 monitoring gap (#10)~~ -- FIXED: now uses 23:59:59

### P2 (Medium Impact)
10. ~~Disconnect `stopTracking()` methods (#16, #17)~~ -- FIXED: targeted shield clearing
11. ~~Use `SharedKeys` constants everywhere (#22)~~ -- FIXED: HandoffManager now uses SharedKeys
12. ~~Consolidate UserDefaults accessors (#23)~~ -- noted, both accessors return same result
13. Replace `NSKeyedArchiver`-based token keys with stable identifiers (#19) -- DEFERRED: needs migration strategy
14. Fix `TicketGroup.cost(for:)` to use settings (#13) -- DEFERRED: costs are intentionally flat per window

### P3 (Cleanup)
15. ~~Remove dead code (#29, #32, #43)~~ -- FIXED
16. Fix deprecated `NavigationView` usage (#38) -- LOW PRIORITY
17. Add accessibility labels (#37) -- LOW PRIORITY
18. ~~Fix `@AppStorage` mismatch (#44)~~ -- FIXED: now uses app group suite
19. ~~Fix double onDismiss (#33)~~ -- FIXED
20. ~~Fix sheet dismiss/present race (#34)~~ -- FIXED: added 0.4s delay
21. ~~Fix double-counting in simulateAppUsage (#12)~~ -- FIXED
22. ~~Fix `TicketGroup.init` overwrites enabledIntervals (#14)~~ -- FIXED
23. ~~Fix authorization status observation (#15)~~ -- FIXED: refreshes on foreground
24. ~~Fix shield rebuild race condition (#8)~~ -- FIXED: separate task variables
25. ~~Fix silent fallback to UserDefaults.standard (#24)~~ -- FIXED: assertionFailure in DEBUG
26. ~~Fix HandoffManager only tries first scheme (#42)~~ -- FIXED: iterates all fallbacks
