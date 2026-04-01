# Full App Audit Report — Steps4 (Nowhere)

**Date:** March 24, 2026
**Scope:** All 123 Swift files across 7 targets — main app, 4 extensions, tests, widget
**Product:** Nowhere.app (Steps4 Xcode project)

---

## Table of Contents

1. [Critical Bugs (P0)](#1-critical-bugs-p0)
2. [High-Priority Bugs (P1)](#2-high-priority-bugs-p1)
3. [Dead Code — Entire Files](#3-dead-code--entire-files)
4. [Dead Code — Functions & Properties](#4-dead-code--functions--properties)
5. [Unused / Redundant Computed Properties](#5-unused--redundant-computed-properties)
6. [Weak Spots — Potential Crashes & Race Conditions](#6-weak-spots--potential-crashes--race-conditions)
7. [Duplicated Logic](#7-duplicated-logic)
8. [Hardcoded Values & Magic Numbers](#8-hardcoded-values--magic-numbers)
9. [Architecture & Design Issues](#9-architecture--design-issues)
10. [UI / Accessibility Issues](#10-ui--accessibility-issues)
11. [Test Coverage Gaps](#11-test-coverage-gaps)
12. [Cleanup / Housekeeping](#12-cleanup--housekeeping)
13. [Summary Checklist](#13-summary-checklist)

---

## 1. Critical Bugs (P0)

### 1.1 `loadDayPassGrants()` never called in bootstrap
- **File:** `AppModel.swift` (line ~356)
- **Impact:** Day passes are lost on every app restart. Users who paid for a day pass lose it after force-quit or reboot.
- **Fix:** Call `loadDayPassGrants()` inside `bootstrap()`.

### 1.2 `loadAppUnlockSettings()` never called
- **File:** `AppModel+AppSettings.swift` (line ~114)
- **Impact:** Per-app unlock settings (entry cost, day pass cost, allowed windows) are never restored from UserDefaults on launch. All customizations reset to defaults every launch.
- **Fix:** Call `loadAppUnlockSettings()` inside `bootstrap()`.

### 1.3 `loadCustomEnergyOptions()` never called in bootstrap
- **File:** `AppModel+DailyEnergy.swift` (line ~74)
- **Impact:** User-created custom energy options vanish after restart. Only called from tests.
- **Fix:** Call `loadCustomEnergyOptions()` inside `bootstrap()`.

### 1.4 `pay(cost:)` caps `spentStepsToday` — contradicts documented invariant
- **File:** `AppModel+Payment.swift` (line ~95)
- **Impact:** `pay(cost:)` caps `spentStepsToday` at `baseEnergyToday`, but `loadSpentStepsBalance()` and `recalculateDailyEnergy()` both say "Do NOT cap spentStepsToday to baseEnergyToday." If a user spends colors, then resets their canvas (lowering base energy), the cap silently erases spent tracking.
- **Fix:** Remove the `min(...)` cap in `pay(cost:)` to match the documented invariant, or update the invariant comments.

### 1.5 Missing `NSHealthShareUsageDescription` in Info.plist
- **File:** `Steps4/Info.plist`
- **Impact:** Only `NSHealthUpdateUsageDescription` (write) is present. HealthKit read authorization will silently fail on iOS without the share (read) description. Step counting won't work for new installs.
- **Fix:** Add `NSHealthShareUsageDescription` key with appropriate description string.

---

## 2. High-Priority Bugs (P1)

### 2.1 `payForEntry` with nil `bundleId` silently loses tracking
- **File:** `AppModel+Payment.swift` (line ~37-38)
- **Impact:** When `bundleId` is nil, cost is deducted from balance but never tracked in `appStepsSpent*` dictionaries. Colors vanish with no audit trail.
- **Fix:** Guard against nil bundleId or track under a "general" key.

### 2.2 `startStepObservation()` not called from bootstrap
- **File:** `AppModel+HealthKit.swift` (line ~47)
- **Impact:** Step observation only starts if `ensureHealthAuthorizationAndRefresh()` is called (from onboarding). Users who already completed onboarding may never get real-time step updates after a fresh install on a new device.
- **Fix:** Call `startStepObservation()` in `bootstrap()` when HealthKit auth is already granted.

### 2.3 Triple `recalculateDailyEnergy()` on every refresh
- **File:** `AppModel+HealthKit.swift` (line ~32-35)
- **Impact:** `refreshStepsIfAuthorized()` triggers `recalculateDailyEnergy()` 2-3 times per call (once in `refreshStepsBalance`, once or twice in `refreshSleepIfAuthorized`). Each recalculation triggers Supabase sync.
- **Fix:** Refactor to recalculate once after both steps and sleep data are fetched.

### 2.4 Widget budget accumulation overwrites `usageBudgetInitial`
- **File:** `UnlockWidget/UnlockGroupWidgetIntent.swift` (line ~55-59)
- **Impact:** If a user taps unlock while budget is already active, the new total overwrites `usageBudgetInitial`. The progress bar denominator is wrong — shows incorrect progress.
- **Fix:** Only overwrite `usageBudgetInitial` when starting a new session (existing budget is 0).

### 2.5 `OnboardingStoriesView.generateFloaters()` RNG bug
- **File:** `StepsTrader/Views/OnboardingStoriesView.swift` (line ~97-100)
- **Impact:** `nextRandom()` is a nested function that captures `var seed` by copy (not by reference). The seed never mutates — all "random" values are the same. Floaters are not actually random.
- **Fix:** Change `nextRandom()` to a closure that captures `seed` by reference, or use `inout`.

### 2.6 `CachedFormatters` is not thread-safe
- **File:** `StepsTrader/Utilities/CachedFormatters.swift`
- **Impact:** `DateFormatter` is not thread-safe per Apple docs. Shared static instances are used from main thread and actor-isolated contexts. Can cause rare crashes under concurrent access.
- **Fix:** Use `Date.FormatStyle` (iOS 15+), or protect with a lock, or make formatters `@MainActor`.

---

## 3. Dead Code — Entire Files

| File | Lines | Reason |
|------|-------|--------|
| `StepsTrader/Views/CategorySettingsView.swift` | ~280 | Never instantiated — zero call sites for `CategorySettingsView(` |
| `StepsTrader/Views/CustomActivityEditorView.swift` | ~232 | Never instantiated — zero call sites |
| `StepsTrader/Views/AutomationGuideView.swift` | ~511 | Never instantiated (even within `#if DEBUG`) |
| `StepsTrader/Views/ColorPaletteView.swift` (partial) | ~144 | `ActivityPickerWithColorSheet` (lines 77-221) is never instantiated |
| `StepsTrader/Services/UnlockExpiryTaskManager.swift` | ~100 | Entire class is a no-op. Comment says "Retained for backward compatibility" — `scheduleIfNeeded()` is empty |
| `Root Info.plist` | 0 | Empty file at project root — accidental creation |

**Total dead code: ~1,200+ lines** that can be safely removed.

---

## 4. Dead Code — Functions & Properties

### AppModel.swift
| Symbol | Line | Issue |
|--------|------|-------|
| `appDisplayName(for:)` | ~319 | Never called from any view or service |
| `loadDayPassGrants()` | ~356 | Exists but never invoked (see P0 bug) |
| `isBlocked` (forwarding property) | ~87 | Never read from any view or service |
| `saveAppSelectionTask` | ~195 | Declared, never used — leftover debounce stub |
| `lastSavedAppSelection` | ~197 | Declared, never read — same stub |

### AppModel+AppSettings.swift
| Symbol | Line | Issue |
|--------|------|-------|
| `updateUnlockSettings(for:tariff:)` | ~64 | Never called anywhere |
| `updateUnlockSettings(for:entryCost:dayPassCost:)` | ~72 | Only called by the above dead overload |
| `deactivateTicket(bundleId:)` | ~104 | Never called |
| `loadAppUnlockSettings()` | ~114 | Exists but never called (see P0 bug) |

### AppModel+BudgetTracking.swift
| Symbol | Line | Issue |
|--------|------|-------|
| `dayPassCost(for:)` | ~17 | Only called by dead `updateUnlockSettings` |

### AppModel+DailyEnergy.swift
| Symbol | Line | Issue |
|--------|------|-------|
| `setDailySleepHours(_:)` | ~694 | Never called from any view |
| `renameRoutine(_:to:)` | ~1034 | Never called from any view |

### AppModel+Payment.swift
| Symbol | Line | Issue |
|--------|------|-------|
| `canPayForEntry(for:costOverride:)` | ~6 | Never called |
| `canPayForDayPass(for:)` | ~12 | Never called |

### AppModel+CloudKit.swift
| Symbol | Line | Issue |
|--------|------|-------|
| Entire file (5 functions) | 1-60 | Potentially all legacy if fully migrated to Supabase — needs confirmation |

### Views
| Symbol | File | Issue |
|--------|------|-------|
| `onOuterWorldTap` | `StepBalanceCard.swift:28` | Optional closure, never wired up at any call site |
| `outerWorldSteps` / `grantedSteps` params | `StepBalanceCard.swift:8-9` | Always passed as `0` at every call site |
| `appsCount` computed property | `InlineTicketSettingsView.swift:115` | Declared but never read |
| `resolvedTitle` @State | `PaperTicketView.swift:21` | Never written to — `titleCache` handles it instead |
| `theme` plain property | `MainTabView.swift:19` | Not from `@Environment`, always `.system` |

### Services
| Symbol | File | Issue |
|--------|------|-------|
| `cancellables` set | `CloudKitService.swift` | Declared but never used |
| `AppFonts` enum | `Font+Custom.swift` | Every property is a direct alias of system fonts — zero value-add |

### Widget
| Symbol | File | Issue |
|--------|------|-------|
| `templateAppScheme` dict | `UnlockWidgetViews.swift:29-41` | Defined but never used in widget views |
| `MediumWidgetMode.app` | `SelectGroupIntent.swift` | Enum case appears unused — only `.stats` is used |

---

## 5. Unused / Redundant Computed Properties

### AppModel+DailyEnergy.swift — Six layers of indirection
| Property | Wraps | Used By |
|----------|-------|---------|
| `activityExtrasPoints` | Direct calculation | `activityPointsToday` |
| `activityPointsToday` | `activityExtrasPoints` | `recalculateDailyEnergy` |
| `creativityExtrasPoints` | Direct calculation | `creativityPointsToday` |
| `creativityPointsToday` | `creativityExtrasPoints` | `recalculateDailyEnergy` |
| `joysChoicePointsToday` | Direct calculation | `joysCategoryPointsToday` |
| `joysCategoryPointsToday` | `joysChoicePointsToday` | `recalculateDailyEnergy` |

**Fix:** Collapse each pair into a single computed property. Remove the `*ExtrasPoints` / `*ChoicePointsToday` intermediaries.

### TicketGroup.swift — Redundant instance method
- Instance `cost(for:)` just calls `Self.cost(for:)` — unnecessary indirection.

---

## 6. Weak Spots — Potential Crashes & Race Conditions

### Force Unwraps & Unsafe Patterns
| File | Issue |
|------|-------|
| `OnboardingStoriesView.swift:1087` | `UIWindow()` fallback in `presentationAnchor()` — empty window can crash |
| `Note.swift` | `NoteCatalog.random()` force-indexes `all[0]` — fragile if catalog emptied |
| `CanvasElement.swift` | `Color.toHex()` uses `UIColor(self)` — can fail for P3/Display-P3 color spaces |
| `Types.swift` | `AppTheme.isLightTheme` reads `UITraitCollection.current` — deprecated iOS 17+, unsafe off main thread |
| `CanvasStorageService.swift` | `storageDirectory` / `snapshotDirectory` are `lazy var` — not thread-safe |

### Race Conditions
| File | Issue |
|------|-------|
| `SupabaseSyncDTOs.swift` | `DayCanvasReadRow.canvasJson` is `Any` — not Sendable, unsafe across actors |
| `UserDefaults+StepsTrader.swift` | `hasLoggedGroupInfo` is a static mutable var without synchronization |
| `UnlockGroupWidgetIntent.swift` | Widget writes to shared UserDefaults while main app may also be writing — no locking |
| `CloudKitService.swift` | Delete-then-insert pattern is not atomic — crash between operations loses data |

### Swallowed Errors
| File | Pattern |
|------|---------|
| `UserEconomyStore` | `try? await` inside Tasks — errors silently ignored |
| `CanvasStorageService` | `saveCanvas` logs errors but callers have no way to know persistence failed |
| `TicketGroup.swift` | `try? JSONEncoder().encode(selection)` — silent failure drops `selectionData` |
| `CloudKitService.swift` | `let (_, _) = try await modifyRecords` — save results discarded |

---

## 7. Duplicated Logic

### 7.1 Token Lookup (NSKeyedArchiver + base64)
- `AppModel+TicketGroups.swift` → `findTicketGroup(for:)` 
- `AppModel+AppSettings.swift` → `unlockSettings(for:)`
- Both do identical NSKeyedArchiver → base64 → UserDefaults lookup. **Extract shared helper.**

### 7.2 StoredUnlockSettings — 3 copies
1. `DeviceActivityMonitorExtension.swift` (line ~103)
2. `ShieldActionExtension.swift` (line ~20)
3. `ShieldRebuildHelper.swift` (line ~67, as `StoredSettings`)

**Fix:** Move to `Shared/` so all targets use one definition.

### 7.3 Group Loading Logic — 3 copies
1. `DeviceActivityMonitorExtension.loadTicketGroupsForExtension()`
2. `ShieldRebuildHelper.loadGroups()`
3. `UnlockTimelineProvider.loadActiveGroupIds()`

**Fix:** Consolidate into `ShieldRebuildHelper.loadGroups()` used by all.

### 7.4 DayBoundary — 2 identical implementations
1. `StepsTrader/Utilities/DayBoundary.swift` (used by main app)
2. `Shared/DayBoundaryCore.swift` (used only by widget)

**Fix:** Delete one. Use `Shared/DayBoundaryCore.swift` everywhere, or promote `DayBoundary` to the Shared folder.

### 7.5 EnergyGradientBackground — repeated boilerplate
The same 6-line initialization pattern is copy-pasted in ~10 views:
```swift
EnergyGradientBackground(
    stepsPoints: model.stepsPointsToday,
    sleepPoints: model.sleepPointsToday,
    hasStepsData: model.hasStepsData,
    hasSleepData: model.hasSleepData
)
.ignoresSafeArea()
.allowsHitTesting(false)
```
Settings pages already extract this into `SettingsGradientBG`. **Apply same pattern to all main tabs.**

### 7.6 `nextResetDate` / `fallbackEntry` — duplicated in widget
Both `UnlockTimelineProvider` and `StatusTimelineProvider` have identical implementations of `nextResetDate` and `fallbackEntry`.
**Extract to a shared helper.**

### 7.7 `persist()` vs `persistDayEnd()` in BudgetEngine
Both write `dayEndHour` / `dayEndMinute` to the same UserDefaults keys. `persistDayEnd()` is redundant since `persist()` always runs.

### 7.8 `logEnergyState` vs `syncStatsToSupabase` in AuthenticationService
Both PATCH the same Supabase endpoint with nearly identical logic. Merge or delegate to one path.

---

## 8. Hardcoded Values & Magic Numbers

| File | Value | Suggestion |
|------|-------|------------|
| `AppModel.swift:279` | `24 * 60 * 60` (stale threshold) | `private static let staleThreshold: TimeInterval = 86_400` |
| `AppModel.swift:321` | `"timeAccessSelection_v1_\(cardId)"` | Move to `SharedKeys` |
| `AppModel.swift:329` | `"fc_appName_"` prefix | Used in 3+ files — make constant |
| `AppModel.swift:391` | `entryCost * 100` | Magic multiplier for day pass cost |
| `AppModel+BudgetTracking.swift` | `0/1000/5000/10000` tariff costs | Move to `Tariff` enum or config struct |
| `AppModel+PayGate.swift:198` | `10` seconds dismiss cooldown | Named constant |
| `AppModel+PayGate.swift:249` | `1000` transaction log cap | Named constant |
| `AppModel+DailyEnergy.swift:854` | `max(total, 30)` rest day minimum | Move to `EnergyDefaults` |
| `Types.swift` | `HandoffToken.isExpired > 60` | Named constant |
| `CanvasElement.swift` | Multiple ranges like `0.08...0.2` | Named constants |
| `GalleryView.swift:794` | `.frame(width: 390, height: 500)` export size | Device-aware sizing |
| `ShieldRebuildHelper.swift:43` | `"appUnlockSettings_v1"` | Use `SharedKeys.appUnlockSettings` |
| `ShieldActionExtension.swift:78` | `"payGateRequestedAt_v1"` | Fragile — not from SharedKeys |
| `UnlockTimelineProvider.swift:156` | `appsCount: 1` | Placeholder never updated |
| `HealthKitService.swift` | `nsError.code == 11` | Use `HKError.Code` constant |

---

## 9. Architecture & Design Issues

### 9.1 SupabaseSyncService is 2,100+ lines
Single-responsibility violation. Split by domain: analytics, selections, preferences, canvas, ticket groups.

### 9.2 TargetResolver uses parallel dictionaries
`targetToBundleId`, `targetToScheme`, `bundleToDisplayName`, `bundleToImageName`, `bundleToScheme` — adding a new app requires updating 5 dictionaries. **Refactor to a single registry struct.**

### 9.3 StepsTraderApp has massive `body`
The `WindowGroup` body contains deeply nested conditional logic and many `.onReceive` modifiers. Hard to maintain. **Extract notification handlers into a coordinator.**

### 9.4 `cleanupTimer` fires every 30 seconds
Calls `model.checkDayBoundary()` every 30s even when unnecessary. Use `scenePhase` + targeted scheduling instead of polling.

### 9.5 No `@Environment(\.scenePhase)` usage
Uses raw `NotificationCenter` publishers for `didEnterBackground`/`willEnterForeground` instead of modern SwiftUI `scenePhase`.

### 9.6 `CanvasStorageService` depends on `GenerativeCanvasView`
The service layer (storage) imports a SwiftUI view for rendering. Rendering should be a separate concern.

### 9.7 `AuthenticationService.avatarData` stored in UserDefaults
Image bytes in UserDefaults bloat the plist. Use file storage instead.

### 9.8 `ColorConstants.swift` contains full views
`ResistanceTag`, `PinkUnderline`, `ThemedDivider`, `EmptyStateView` are SwiftUI views living in a "constants" file. Move to `Views/Components/`.

### 9.9 `LocationPermissionRequester` may be redundant
Only has `requestWhenInUse()`. `ProfileLocationManager` handles the same use case. Verify if both are needed.

### 9.10 `AppModel+CloudKit.swift` — entire extension may be legacy
All 5 functions are only called from `CloudKitService.swift`. If fully migrated to Supabase, the whole CloudKit layer is dead weight.

---

## 10. UI / Accessibility Issues

### No Dynamic Type Support
| File | Element |
|------|---------|
| `OnboardingStoriesView.swift` | Font sizes `18, 20, 32, 60, 16` — all hardcoded |
| `MainTabView.swift:298-303` | Tab bar icons `24/22`, text `size: 11` — fixed |
| `PayGateView.swift` | `isCompact = height < 700`, button `.frame(height: 56)` — fixed |
| `PaperTicketView.swift:103` | `.frame(height: 80)` — clips with large text |
| `LoginView.swift` | `width: 300`, `height: 300`, `100x100` — won't fit SE screens |

### Below Accessibility Minimum (44pt)
| File | Element | Size |
|------|---------|------|
| `ColorPaletteView.swift:59` | Color dots | 32x32 |
| `OptionEntrySheet.swift` | Shape picker buttons | 40x40 |

### Other
| File | Issue |
|------|-------|
| `GalleryView.swift:794` | Export hardcoded to 390x500 — wrong on iPad |
| `DayEndSettingsView.swift:119` | `Calendar.current.date(from: comps) ?? Date()` — semantically wrong fallback |

---

## 11. Test Coverage Gaps

| Area | Missing Coverage |
|------|-----------------|
| `DayBoundaryCore` (Shared/) | Zero tests — `DayBoundaryTests` tests `DayBoundary`, not `DayBoundaryCore` |
| `BudgetEngine.resetIfNeeded()` | No test for day-boundary reset behavior |
| `Tariff.free.stepsPerMinute` | Not tested — `stepsPerMinute` returns `100` for free which is same as easy, but `minutes(from:)` would give wrong results |
| HealthKit auth `.notDetermined` | No test for what happens when `refreshStepsIfAuthorized` is called with undetermined auth |
| `DailyEnergyLogicTests` | Tests private formula replicas, not actual `AppModel` methods — drift risk if formulas change |
| `SharedMocks.sendMinuteModeSummary` | References `MinuteChargeLog` which was deleted — verify protocol still requires it |
| `MockFamilyControlsService` | No verification flags (`called` booleans) — can't assert invocations |
| Widget timeline | Zero tests for `UnlockTimelineProvider` or `StatusTimelineProvider` |
| Extension entry points | Zero tests for DeviceActivityMonitor, ShieldAction, ShieldConfiguration |

---

## 12. Cleanup / Housekeeping

### Files to Delete
- [ ] `Root Info.plist` (empty file at project root)
- [ ] `CategorySettingsView.swift` (dead view, ~280 lines)
- [ ] `CustomActivityEditorView.swift` (dead view, ~232 lines)
- [ ] `AutomationGuideView.swift` (dead view, ~511 lines)
- [ ] `ActivityPickerWithColorSheet` in `ColorPaletteView.swift` (dead code, ~144 lines)
- [ ] `UnlockExpiryTaskManager.swift` (no-op class, ~100 lines)

### Legacy Code to Evaluate
- [ ] `AppModel+AppSelection.swift` lines 41-68: `NSKeyedUnarchiver` fallback for `persistentApplicationTokens` — still needed?
- [ ] `AppModel+CloudKit.swift`: Entire file — still needed after Supabase migration?
- [ ] `LocationPermissionRequester.swift`: Redundant with `ProfileLocationManager`?
- [ ] `StatusViewModels.swift`: `#if DEBUG` only — any non-debug consumers?
- [ ] `StatusViewHelpers.swift`: `#if DEBUG` only — same question

### UserDefaults Key Hygiene
- [ ] Move all raw string keys to `SharedKeys`
- [ ] Eliminate `UserDefaults.standard` usage where app group is intended (`Note.swift`, `AuthenticationService.swift`)
- [ ] Remove `persistDayEnd()` in `BudgetEngine` (duplicate of `persist()`)
- [ ] Remove double-write `tariff` didSet in `BudgetEngine` after migration period

### Silenced Errors to Fix
- [ ] `UserEconomyStore`: Replace `try? await` with proper error handling or logging
- [ ] `CanvasStorageService.saveCanvas`: Propagate errors to callers
- [ ] `TicketGroup` encode: Log when `selectionData` encoding fails
- [ ] `CloudKitService`: Check `modifyRecords` results for individual failures

---

## 13. Summary Checklist

### Critical (fix immediately)
- [x] Call `loadDayPassGrants()` in `bootstrap()`
- [x] Call `loadAppUnlockSettings()` in `bootstrap()`
- [x] Call `loadCustomEnergyOptions()` in `bootstrap()`
- [x] Fix `pay(cost:)` cap vs. documented invariant
- [x] Add `NSHealthShareUsageDescription` to `Steps4/Info.plist`

### High Priority
- [x] Fix nil `bundleId` in `payForEntry` — track or guard
- [x] Call `startStepObservation()` in `bootstrap()` when already authorized
- [x] Refactor `refreshStepsIfAuthorized()` to recalculate once
- [x] Fix widget `usageBudgetInitial` overwrite
- [x] Fix `generateFloaters()` RNG bug in onboarding
- [x] Make `CachedFormatters` thread-safe

### Medium Priority (dead code removal)
- [x] Delete 5 dead files (~1,200 lines)
- [x] Remove ~15 dead functions across AppModel extensions
- [x] Collapse 6 redundant computed properties in DailyEnergy
- [x] Consolidate 3 copies of `StoredUnlockSettings`
- [x] Merge duplicate `DayBoundary` / `DayBoundaryCore`
- [x] Extract duplicate token lookup into shared helper — already done, no duplication
- [x] Extract `EnergyGradientBackground` boilerplate into reusable modifier

### Low Priority (code quality)
- [x] Split `SupabaseSyncService` into domain-specific files — already split into 7 extensions
- [x] Refactor `TargetResolver` to single registry struct
- [x] Move hardcoded values to named constants (SharedKeys)
- [x] Add Dynamic Type support to onboarding and tab bar
- [x] Move views out of `ColorConstants.swift`
- [x] Add test coverage for `DayBoundary`, BudgetEngine, Tariff
- [x] Move avatar storage from UserDefaults to file system — already done
- [x] Modernize to `@Environment(\.scenePhase)` — already done
