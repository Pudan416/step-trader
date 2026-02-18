# HealthKit Integration Audit

**Date:** 2026-02-17  
**App:** Steps4 (DOOM CTRL / StepsTrader)  
**Scope:** All HealthKit / Health app touchpoints

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Views                        │
│  (15+ views read stepsToday, dailySleepHours, etc.)    │
└──────────────────────┬──────────────────────────────────┘
                       │ @EnvironmentObject / model.*
┌──────────────────────▼──────────────────────────────────┐
│                     AppModel                            │
│  - Forwards healthStore.stepsToday, .dailySleepHours    │
│  - recalculateDailyEnergy() uses steps + sleep          │
│  - Extension: AppModel+HealthKit.swift                  │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│                   HealthStore                           │
│  - @MainActor ObservableObject                          │
│  - Wraps HealthKitServiceProtocol                       │
│  - Manages caching, observation lifecycle               │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│                HealthKitService                         │
│  - Concrete HKHealthStore interaction                   │
│  - Authorization, queries, background delivery          │
│  - Injected via DIContainer → HealthKitServiceProtocol  │
└─────────────────────────────────────────────────────────┘
```

**Layering verdict:** Clean 3-layer separation (Service → Store → ViewModel). Protocol-based DI makes testing straightforward.

---

## 2. Data Types Read from HealthKit

| HK Type | Identifier | Access | Used For |
|---------|-----------|--------|----------|
| `HKQuantityType` | `.stepCount` | **Read only** | Step balance, energy points, budget minutes |
| `HKCategoryType` | `.sleepAnalysis` | **Read only** | Sleep hours, sleep points, energy calculation |

**No write access** — the app requests `toShare: []` (empty set). Authorization request uses `read: [stepType, sleepType]`.

---

## 3. Entitlements & Info.plist

### Entitlements (`Steps4.entitlements`)

| Key | Value | Status |
|-----|-------|--------|
| `com.apple.developer.healthkit` | `true` | OK |
| `com.apple.developer.healthkit.background-delivery` | `true` | OK |

### Info.plist (via project.pbxproj)

| Key | Value | Status |
|-----|-------|--------|
| `NSHealthShareUsageDescription` | "DOOM CTRL needs access to your step count to manage app time." | **Warning** — mentions steps only, not sleep |
| `NSHealthUpdateUsageDescription` | "DOOM CTRL uses your step count to calculate available time." | **Warning** — set but unused (app never writes) |

### Issues Found

- **P1: Usage description doesn't mention sleep.** The app reads `sleepAnalysis` but the privacy string only says "step count." Apple reviewers may flag this, and users don't get informed about sleep data access.
- **P2: `NSHealthUpdateUsageDescription` is unnecessary.** The app passes `toShare: []` — it never writes to HealthKit. Having this key is misleading and could cause a review question.

---

## 4. Authorization Flow

### Entry Point

`OnboardingFlowView` → calls `model.ensureHealthAuthorizationAndRefresh()` after onboarding completes.

### Flow

```
ensureHealthAuthorizationAndRefresh()
  ├─ healthStore.requestAuthorization()
  │    └─ HealthKitService.requestAuthorization()
  │         ├─ HKHealthStore.isHealthDataAvailable() guard
  │         ├─ statusForAuthorizationRequest() (iOS 15+)
  │         ├─ store.requestAuthorization(toShare: [], read: [steps, sleep])
  │         ├─ enableBackgroundDelivery(steps, .immediate)
  │         └─ enableBackgroundDelivery(sleep, .immediate)
  ├─ refreshStepsBalance()
  ├─ refreshSleepIfAuthorized()
  └─ startStepObservation()
```

### Safety Mechanisms

- **Duplicate request guard:** `isRequestingAuthorization` flag prevents concurrent calls.
- **Timeout watchdog:** 5-second `Task` resets the flag if completion never fires.
- **Error handling:** `ErrorManager.shared.handle(AppError.healthKitAuthorizationFailed(error))` on failure.
- **Graceful degradation:** If auth fails, fetches are still attempted (read access isn't reliably reported by `authorizationStatus()`).

### Issues Found

- **P3: Authorization status is checked via `authorizationStatus(for:)` which reports WRITE status, not READ.** The code correctly documents this in comments and works around it by always attempting to fetch. However, the `authorizationStatus` property on `HealthStore` is still of type `HKAuthorizationStatus` and is exposed to the UI — this can mislead the developer (the value will typically be `.sharingDenied` for read-only apps even when read is granted).
- **P4: `requestAuthorization` uses `withCheckedThrowingContinuation` wrapping the completion-based API.** While functional, Apple now provides `store.requestAuthorization(toShare:read:)` as a native async method on iOS 15+. The continuation wrapper adds complexity.

---

## 5. Step Count Implementation

### Fetching

- **Query type:** `HKStatisticsQuery` with `.cumulativeSum` — correct for step aggregation.
- **Predicate:** `HKQuery.predicateForSamples(withStart:end:options: .strictStartDate)` — good, prevents samples from before the window being included.
- **Day window:** Uses custom `DayBoundary` (user-configurable day-end time), NOT midnight. `HealthStore.currentDayStart(for:)` reads `dayEndHour_v1` / `dayEndMinute_v1` from UserDefaults.

### Real-time Observation

- **Query type:** `HKAnchoredObjectQuery` — correct for incremental updates.
- **Predicate start:** `Date.startOfToday` (custom day boundary aware).
- **Update handler:** Accumulates `lastStepCount += added` and dispatches to `@MainActor`.
- **Initial fetch:** `fetchTodaySteps()` called before anchored query starts — ensures UI isn't blank.

### Caching

- Cached to UserDefaults (`cachedStepsToday` key) in app group.
- Separate `hasStepsData_v1` boolean flag — distinguishes "zero steps fetched" from "never fetched."
- On fetch failure, falls back to cached value.
- `DeviceActivityMonitorExtension` reads `spentStepsToday` from shared UserDefaults.

### Issues Found

- **P5: `Date.startOfToday` inconsistency.** `HealthKitService.fetchTodaySteps()` and `beginObservation()` use `Date.startOfToday` (a computed property on `Date` that reads `dayEndHour_v1`). But `HealthStore.fetchStepsForCurrentDay()` computes its own `currentDayStart(for:)`. Both read the same UserDefaults keys but through different code paths. If either path fails to read the defaults (e.g., app group not available), they could silently disagree on the day window.
- **P6: Anchored query accumulation bug risk.** `lastStepCount += added` in the anchored query update handler is additive. If the query re-delivers samples (e.g., after a background wake), steps could be double-counted. There's no deduplication by sample UUID. Speculation: this may only manifest in edge cases with aggressive background delivery.
- **P7: `fetchTodaySteps()` and `fetchTodaySleep()` exist on `HealthKitServiceProtocol` but are never called by `HealthStore`.** `HealthStore` always calls `fetchSteps(from:to:)` with its own computed day start. These methods are dead code from the service's perspective (only used internally by `startObservingSteps`'s initial fetch).

---

## 6. Sleep Analysis Implementation

### Fetching

- **Query type:** `HKSampleQuery` — appropriate for category samples.
- **Predicate:** `HKQuery.predicateForSamples(withStart:end:options: [])` — no strict start, allows overlapping sleep sessions that began before the window.
- **Sample filtering (iOS 16+):** Only counts `asleepUnspecified`, `asleepCore`, `asleepDeep`, `asleepREM`. Explicitly excludes `inBed` to prevent double-counting.
- **Sample filtering (< iOS 16):** Falls back to `.asleep` only.
- **Overlap handling:** Clips each sample to `[start, end]` window via `max(sample.startDate, start)` / `min(sample.endDate, end)`.

### Issues Found

- **P8: No deduplication of overlapping sleep samples.** If multiple sources (Apple Watch + iPhone) record overlapping sleep sessions, the hours are summed without merging. Example: Watch records asleepCore 23:00–06:00 (7h) and iPhone records asleepUnspecified 23:30–05:30 (6h) → total = 13h instead of ~7h. Apple's own Health app merges these.
- **P9: No background refresh for sleep.** Background delivery is enabled for sleep type, but there's no `HKObserverQuery` for sleep — only for steps. Sleep data is only fetched on `refreshSleepIfAuthorized()` which happens at app launch / foreground. If the user opens the app before their watch syncs sleep data, they'll see 0 hours until next manual refresh.
- **P10: Sleep predicate uses empty options `[]`.** This means samples that START before the window but END within it are included. This is intentional (overnight sleep starts yesterday), but combined with the overlap clipping it could include very old samples whose endDate falls within today's window.

---

## 7. Background Delivery

| Type | Frequency | Registered In |
|------|-----------|---------------|
| Step count | `.immediate` | `HealthKitService.requestAuthorization()` |
| Sleep analysis | `.immediate` | `HealthKitService.requestAuthorization()` |

### Issues Found

- **P11: Background delivery is enabled but there's no `HKObserverQuery` registered for background wake.** `enableBackgroundDelivery` tells HealthKit to wake the app, but the app needs an `HKObserverQuery` with a background completion handler to actually receive the wake. The `HKAnchoredObjectQuery` used for steps is a foreground query — it won't fire when the app is suspended. The background delivery registration is effectively a no-op.
- **P12: Background delivery for sleep is enabled but never used.** No observer or anchored query exists for sleep data at all.

---

## 8. Data Flow: Steps → Energy System

```
Raw steps (Double) 
  → pointsFromSteps(): capped at userStepsTarget (default 10,000)
  → ratio × 20 (max points)

Raw sleep hours (Double)
  → pointsFromSleep(): capped at userSleepTarget (default 8h)
  → ratio × 20 (max points)

Total daily energy = stepsPoints(20) + sleepPoints(20) + body(20) + mind(20) + heart(20) = 100 max
```

### Targets (configurable by user)

| Metric | Default | Key | Max Points |
|--------|---------|-----|-----------|
| Steps | 10,000 | `userStepsTarget` | 20 |
| Sleep | 8 hours | `userSleepTarget` | 20 |

### Sync to Supabase

Steps and sleep data are synced to Supabase via `SupabaseSyncService`:
- `syncDailyStats()` — real-time sync on every `recalculateDailyEnergy()` call
- `syncDaySnapshot()` — end-of-day snapshot when day resets
- `loadTodayStatsFromServer()` — bootstrap from server on fresh install / new device

### Shared with Extension

- `cachedStepsToday` → app group UserDefaults → read by `DeviceActivityMonitorExtension`
- `spentStepsToday` → app group UserDefaults → read by extension for minute-mode charging

---

## 9. Error Handling

| Error Case | Handling |
|-----------|---------|
| HealthKit not available | Throws `HealthKitServiceError.healthKitNotAvailable` |
| Step type unavailable | Throws `HealthKitServiceError.stepTypeNotAvailable` |
| Sleep type unavailable | Throws `HealthKitServiceError.sleepTypeNotAvailable` |
| Auth failed | `ErrorManager.shared.handle(AppError.healthKitAuthorizationFailed(error))` |
| Fetch steps failed | Logs warning, falls back to `lastStepCount` or cached |
| Fetch sleep failed | Logs warning, returns 0 |
| HK error code 11 | Returns cached step count (no data available) |

**Verdict:** Error handling is reasonable. Graceful degradation with caching. No crashes on failure paths.

---

## 10. Testing

### Current Coverage

- `CustomActivityTests.swift` includes `MockHealthKitService` implementing full `HealthKitServiceProtocol`.
- Mock returns 0 for all fetches, `.sharingAuthorized` for status.
- Tests cover AppModel integration but **not** HealthKit-specific behavior.

### Issues Found

- **P13: No unit tests for `HealthStore` or `HealthKitService`.** The mock is used only to satisfy AppModel's DI — there are no tests verifying step calculation, sleep aggregation, caching, or observation behavior.
- **P14: Mock always returns `.sharingAuthorized`.** Tests never exercise the `.notDetermined` or `.sharingDenied` paths.

---

## 11. Files Touched

### Core (4 files)

| File | Role |
|------|------|
| `StepsTrader/Services/HealthKitService.swift` | HKHealthStore interaction, queries, observation |
| `StepsTrader/Stores/HealthStore.swift` | ObservableObject wrapping service, caching |
| `StepsTrader/AppModel+HealthKit.swift` | AppModel extension bridging health store |
| `StepsTrader/Models/Types.swift` | `HealthKitServiceProtocol` definition |

### Configuration (2 files)

| File | Role |
|------|------|
| `StepsTrader/Steps4.entitlements` | HealthKit + background delivery entitlements |
| `Steps4.xcodeproj/project.pbxproj` | Privacy usage descriptions |

### Data Models (2 files)

| File | Role |
|------|------|
| `StepsTrader/Models/DailyEnergy.swift` | `PastDaySnapshot` (steps + sleep), `EnergyDefaults` |
| `StepsTrader/Models/CanvasElement.swift` | Canvas with `sleepPoints`, `stepsPoints` |

### Supporting (6 files)

| File | Role |
|------|------|
| `StepsTrader/AppModel.swift` | Holds `healthStore`, forwards published properties |
| `StepsTrader/AppModel+DailyEnergy.swift` | `recalculateDailyEnergy()` — consumes steps/sleep |
| `StepsTrader/Services/ErrorManager.swift` | `AppError.healthKitAuthorizationFailed` |
| `StepsTrader/Services/SupabaseSyncService.swift` | Syncs steps/sleep to backend |
| `StepsTrader/Utilities/SharedKeys.swift` | UserDefaults keys for caching |
| `StepsTrader/Utilities/Date+Today.swift` | `Date.startOfToday` using custom day boundary |

### Views (15+ files)

| File | Health Data Used |
|------|-----------------|
| `Views/Components/StepBalanceCard.swift` | Steps, sleep points |
| `Views/Components/DailyEnergyCard.swift` | Sleep hours, manual sleep entry |
| `Views/Components/EnergyGradientBackground.swift` | `hasStepsData`, `hasSleepData` |
| `Views/ChoiceView.swift` | `stepsToday`, `dailySleepHours` |
| `Views/GalleryView.swift` | Steps, sleep in gallery |
| `Views/MainTabView.swift` | Steps, sleep points passed to children |
| `Views/GenerativeCanvasView.swift` | `hasStepsData`, `hasSleepData`, points |
| `Views/SettingsSheet.swift` | Health data display, test overrides |
| `Views/QuickStatusView.swift` | `effectiveStepsToday` |
| `Views/HandoffProtectionView.swift` | Effective steps |
| `Views/OnboardingFlowView.swift` | Triggers `ensureHealthAuthorizationAndRefresh()` |
| `Views/MeView.swift` | Gradient background driven by health data |
| `Views/CategoryDetailView.swift` | Gradient background |
| `Views/AppsPageSimplified.swift` | Gradient background |
| `Views/ManualsPage.swift` | Gradient background |

### Extension (1 file)

| File | Role |
|------|------|
| `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift` | Reads `spentStepsToday` from shared defaults |

### Tests (2 files)

| File | Role |
|------|------|
| `Steps4Tests/CustomActivityTests.swift` | `MockHealthKitService` for DI |
| `Steps4Tests/HealthKitTests.swift` | Dedicated HealthKit unit tests (interval merging, HealthStore behavior, parameterized mock) |

---

## 12. Issue Summary

### High Priority — FIXED

| # | Issue | Status | What Changed |
|---|-------|--------|--------------|
| P1 | `NSHealthShareUsageDescription` doesn't mention sleep | **FIXED** | Updated to mention both steps and sleep |
| P8 | No sleep sample deduplication | **FIXED** | Added `mergedDuration()` interval-merge algorithm in `fetchSleep()` |
| P11 | Background delivery enabled but no `HKObserverQuery` | **FIXED** | Replaced `HKAnchoredObjectQuery` with `HKObserverQuery` that calls `completionHandler()` |

### Medium Priority — FIXED

| # | Issue | Status | What Changed |
|---|-------|--------|--------------|
| P2 | `NSHealthUpdateUsageDescription` set but app never writes | **FIXED** | Removed from both Debug and Release build settings |
| P5 | Two different code paths compute "day start" | **FIXED** | Added `DayBoundary.storedDayEnd()` as single source; `Date.startOfToday` and `HealthStore` both use it |
| P6 | Anchored query accumulation without dedup | **FIXED** | Observer now re-fetches via `HKStatisticsQuery` instead of accumulating deltas |
| P9 | No background refresh for sleep | **N/A** | Already handled — `handleAppWillEnterForeground()` calls `refreshSleepIfAuthorized()` |
| P12 | Background delivery registered for sleep but never consumed | **FIXED** | Removed sleep background delivery registration |

### Low Priority — FIXED

| # | Issue | Status | What Changed |
|---|-------|--------|--------------|
| P3 | `HKAuthorizationStatus` exposed as write-status | **FIXED** | Added doc comments on protocol clarifying write-only semantics |
| P4 | Continuation wrapper instead of native async API | **FIXED** | Replaced with native `store.requestAuthorization(toShare:read:)`. Removed timeout watchdog |
| P7 | Dead `fetchTodaySteps()` / `fetchTodaySleep()` on protocol | **FIXED** | Removed from protocol, service, and mock |
| P10 | Sleep predicate includes very old samples | **FIXED** | Added 24h lookback clamp in `fetchSleep()` |
| P13 | No dedicated HealthKit unit tests | **FIXED** | Added `HealthKitTests.swift` with 20 tests: 8 interval-merging + 12 HealthStore behavior |
| P14 | Mock always returns `.sharingAuthorized` | **FIXED** | Introduced `ConfigurableHealthKitMock` with settable `authStatus`/`sleepAuthStatus`, error injection, observer simulation |

---

## 13. Changes Made

### `project.pbxproj` (both Debug + Release)
- Updated `NSHealthShareUsageDescription` to mention steps **and** sleep
- Removed `NSHealthUpdateUsageDescription` (app never writes to HealthKit)

### `HealthKitService.swift`
- **Sleep deduplication (P8):** Collect intervals, merge overlapping ones via `mergedDuration()`, then sum
- **24h lookback (P10):** `clampedStart = max(start, end - 24h)` prevents ancient samples
- **Observer query (P6/P11):** Replaced `HKAnchoredObjectQuery` with `HKObserverQuery` + `HKStatisticsQuery` re-fetch
- **Native async auth (P4):** Replaced continuation wrapper with `store.requestAuthorization(toShare:read:)`
- **Removed sleep background delivery (P12):** No observer exists, sleep refreshes on foreground
- **Removed dead code:** `fetchTodaySteps()`, `fetchTodaySleep()`, `stepsAnchor`, `authTimeoutTask`
- **Removed dead `#available(iOS 12.0, *)` guards**

### `Types.swift` (HealthKitServiceProtocol)
- Removed `fetchTodaySteps()` and `fetchTodaySleep()` from protocol (P7)
- Added doc comments on `authorizationStatus()` and `sleepAuthorizationStatus()` explaining write-only semantics (P3)

### `DayBoundary.swift`
- Added `storedDayEnd()` — single source of truth for reading day-end hour/minute from UserDefaults (P5)

### `Date+Today.swift`
- Updated `startOfToday` and `isToday` to use `DayBoundary.storedDayEnd()` (P5)

### `HealthStore.swift`
- Updated `currentDayStart(for:)` to use `DayBoundary.storedDayEnd()` (P5)

### `CustomActivityTests.swift`
- Removed `fetchTodaySteps()` and `fetchTodaySleep()` from mock (P7)

### `HealthKitTests.swift` (NEW)
- **`ConfigurableHealthKitMock`** — parameterized mock with settable steps/sleep values, error injection, auth status variants, and observer simulation (P14)
- **`SleepIntervalMergingTests`** (8 tests) — empty, single, non-overlapping, fully overlapping, partially overlapping, adjacent, unsorted, and many-source scenarios against `mergedDuration()` (P13)
- **`HealthStoreTests`** (12 tests) — step fetch + caching, zero-steps validity, cache fallback on error, sleep fetch + error handling, all three auth statuses, observer start/stop/callback (P13)
