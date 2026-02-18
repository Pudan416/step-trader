# Proof (Steps4) — Full Application Audit v2

**Date:** February 15, 2026  
**Scope:** Post-fix re-audit — complete iOS app, Supabase integration, Admin Panel, Telegram Bot, all extensions

---

## Table of Contents

1. [Fix Verification Summary](#fix-verification-summary)
2. [Remaining Bugs](#remaining-bugs)
3. [Remaining Dead Code](#remaining-dead-code)
4. [Remaining Performance Bottlenecks](#remaining-performance-bottlenecks)
5. [Remaining State Management Issues](#remaining-state-management-issues)
6. [Remaining Security Concerns](#remaining-security-concerns)
7. [Duplicate Utility Functions (6 Clusters)](#duplicate-utility-functions-6-clusters)
8. [Filename Mismatches](#filename-mismatches)
9. [Remaining Difficulty Level References](#remaining-difficulty-level-references)
10. [Optimization Opportunities](#optimization-opportunities)
11. [Priority Matrix](#priority-matrix)

---

## Fix Verification Summary

### Confirmed Fixed (22 items)

| Original Issue | Status |
|----------------|--------|
| Notification flood in `schedulePeriodicNotifications()` | **FIXED** — stable identifier, no recursion |
| Admin session cookie was static `"1"` | **FIXED** — HMAC-signed tokens with expiry, constant-time comparison, rate limiting |
| Telegram webhook no secret validation | **FIXED** — `X-Telegram-Bot-Api-Secret-Token` header check added |
| `isNicknameUnique` checked `.length` on wrong object | **FIXED** — correctly checks `data.length === 0` |
| `/api/health` leaked stats and errors | **FIXED** — returns only `{ ok, status }` |
| `normalizeMode` swapped minute/entry labels | **FIXED** — passthrough function now |
| `sumEnergyDelta` full table scan | **FIXED** — Supabase RPC with client-side fallback |
| Admin panel was read-only | **FIXED** — ban/unban/grant energy operations added |
| `updateTotalStepsBalance()` was empty | **FIXED** — implemented in UserEconomyStore |
| `setAppAsTarget` identical branches | **FIXED** — removed entirely |
| `hasDayPass` had write side effects | **FIXED** — pure read function now |
| `moveOtherToEnd`/`moveOtherIdsToEnd` identity functions | **FIXED** — removed |
| `MinuteChargeLog` UUID-per-access identity bug | **FIXED** — stored `let id = UUID()` |
| `AppTheme.isLightTheme` wrong for system dark mode | **FIXED** — uses `UITraitCollection` |
| Duplicate `SupabaseConfig` in two services | **FIXED** — unified in NetworkClient |
| `ISO8601DateFormatter` created per sync | **FIXED** — uses `CachedFormatters.iso8601` |
| DateFormatters in `DayBoundary` not cached | **FIXED** — uses `CachedFormatters.dayKey` |
| `Date+Today.swift` depended on AppModel | **FIXED** — uses `DayBoundary` directly |
| `waitForInitialization` polling loop | **FIXED** — uses `withCheckedContinuation` |
| `currentSupabaseAccessToken` duplicate | **FIXED** — removed |
| `notoSerif()` misleading name | **FIXED** — renamed to `systemSerif()`, deprecated wrapper |
| Font candidate not cached | **FIXED** — `resolvedFontNames` cache dictionary |
| Private API `NSXPCConnection.suspend` | **FIXED** — removed |
| `sendBlockedAppPushNotifications` dead code in extension | **FIXED** — removed |
| Dead code in Views (statusPill, TicketShape, etc.) | **FIXED** — all removed |
| Dead code in GenerativeCanvasView | **FIXED** — `luminanceTintedAssetImage`, `drawSoftLine`, `heartCenter` removed |
| `Localization.swift` was empty | **FIXED** — now contains `countryFlag()` |
| `paletteHex` typo `"#FFD369?"` | **FIXED** — corrected |
| `CachedFormatters.swift` created | **FIXED** — centralized formatter caching |

---

## Remaining Bugs

### BUG-R01: `clearExpiredDayPasses()` Uses Wrong Day Boundary (HIGH)

**File:** `Stores/UserEconomyStore.swift:235-249`

The `UserEconomyStore` version uses `Calendar.current.startOfDay` (midnight), while the rest of the app uses custom day boundaries (`dayEndHour`/`dayEndMinute`). For a user with `dayEndHour = 2`:
- A day pass purchased at 1 AM should be valid until 2 AM the next night
- `UserEconomyStore` expires it at midnight — **1 hour early**

This is called from `loadDayPassGrants()` during bootstrap, meaning passes may vanish on app launch.

```swift
// UserEconomyStore (WRONG):
let dayStart = Calendar.current.startOfDay(for: now)  // midnight

// AppModel+Payment (CORRECT):
let today = currentDayStart(for: Date())  // custom boundary
```

**Fix:** Use `DayBoundary.currentDayStart()` in `UserEconomyStore.clearExpiredDayPasses()`.

---

### BUG-R02: HandoffManager Defaults Unknown Apps to Instagram (HIGH)

**File:** `HandoffManager.swift:68-82`

`bundleScheme(for:)` duplicates `TargetResolver.bundleToScheme` AND has a wrong fallback:

```swift
return map[bundleId] ?? "instagram://app"
```

If a FamilyControls-selected app has an unknown bundle ID, handoff opens **Instagram** instead of the intended app.

**Fix:** Use `TargetResolver.urlScheme(forBundleId:)` and handle nil (show error or skip handoff).

---

### BUG-R03: `applyFamilyControlsSelection` Is a No-Op Called from UI (MEDIUM)

**File:** `AppModel+TicketManagement.swift:20-22`

```swift
func applyFamilyControlsSelection(for bundleId: String) {
    // No-op: selection is now managed via ticket groups
}
```

Still called from `AutomationGuideView.swift` (lines 88, 321). Users pressing those buttons get **zero response** — no error, no feedback, no action.

**Fix:** Either implement the correct action or remove the buttons that call it.

---

### BUG-R04: `scheduleSupabaseTicketUpsert` Is a TODO Stub Called 4x (MEDIUM)

**File:** `AppModel+TicketManagement.swift:42-44`

```swift
func scheduleSupabaseTicketUpsert(bundleId: String) {
    // TODO: Implement Supabase ticket sync
}
```

Called from `setFamilyControlsModeEnabled`, `setMinuteTariffEnabled`, `updateUnlockSettings`, `updateAccessWindow`. Every settings change that should sync to Supabase silently does nothing.

**Fix:** Implement the sync, or route through existing `SupabaseSyncService.syncTicketGroups()`.

---

### BUG-R05: `loadDailyTariffSelections()` Never Called — State Lost on Restart (MEDIUM)

**File:** `AppModel+BudgetTracking.swift:81-100`

A fully implemented 20-line function that loads tariff selections from UserDefaults — but it's **never called** from `bootstrap()` or anywhere else. Daily tariff selections reset silently on every app restart.

**Fix:** Call from bootstrap, or remove if no longer needed.

---

### BUG-R06: HealthStore 0-Step Cached Data (LOW)

**File:** `Stores/HealthStore.swift:94-100`

`loadCachedStepsToday()` only sets `hasStepsData = true` if cached > 0. A legitimate zero-step morning would leave `hasStepsData = false`, potentially showing a "no data" state instead of "0 steps."

**Fix:** Cache a separate boolean flag, or use `-1` sentinel for "no cached data."

---

### BUG-R07: `onOpenURL` Handler Is a Logger-Only Stub (LOW)

**File:** `StepsTraderApp.swift:136-138`

```swift
.onOpenURL { url in
    AppLogger.app.debug("🔗 App received URL: \(url)")
}
```

Deep links and universal links are silently discarded. Either implement URL routing or remove the handler.

---

### BUG-R08: Tautological Assertion (COSMETIC)

**File:** `AppModel+DailyEnergy.swift:894`

```swift
let total = stepsPts + sleepPts + activityPointsToday + creativityPointsToday + joysCategoryPointsToday
assert(total == stepsPts + sleepPts + activityPointsToday + creativityPointsToday + joysCategoryPointsToday)
```

Asserts a variable equals the expression it was just assigned from. Can never fail.

---

## Remaining Dead Code

### AppModel Layer

| Item | File | Lines | Notes |
|------|------|-------|-------|
| `serverGrantedStepsKey` constant | AppModel.swift | 55 | Never referenced — literal `"serverGrantedSteps_v1"` used directly |
| `cacheStepsToday()` no-op | AppModel+HealthKit.swift | 42-44 | Called from `recalcSilently` but body is empty |
| `loadCachedStepsToday()` no-op | AppModel+HealthKit.swift | 46-48 | Empty body, never called externally |
| `disableFamilyControlsShield()` | AppModel+TicketManagement.swift | 24-26 | Never called, misleadingly named (calls rebuild, not disable) |
| `syncEntryCostWithTariff()` | AppModel+BudgetTracking.swift | 141-145 | Never called |
| `refreshMinuteChargeLogs()` | AppModel+BudgetTracking.swift | 61-63 | Never called |

### Models Layer

| Item | File | Notes |
|------|------|-------|
| `ElementKind.softLine` | CanvasElement.swift:8 | Defined in enum but never spawned — `spawn()` only produces `.circle` and `.ray` |
| `CanvasColorPalette.palette` (`[Color]` array) | CanvasElement.swift:266-271 | All callers use `paletteHex` (`[String]`) instead |
| `AppTheme.displayNameRu` | Types.swift:189-195 | No callers, returns English strings anyway |

### Services Layer

| Item | File | Notes |
|------|------|-------|
| `classifyFailure()` method | NetworkClient.swift:118-132 | No callers in entire codebase |
| `FailureKind` enum | NetworkClient.swift:43-49 | Only used by dead `classifyFailure` |

### Stores Layer

| Item | File | Notes |
|------|------|-------|
| `loadSpentStepsBalance()` | UserEconomyStore.swift:67-96 | Private, never called within the class |

### Utilities Layer

| Item | File | Notes |
|------|------|-------|
| `notoSerif()` deprecated wrapper | Font+Custom.swift:14-21 | Deprecated, zero callers — safe to delete |

### Views Layer

| Item | File | Notes |
|------|------|-------|
| `LiquidDotsView` (79 lines) | RadialHoldMenu.swift:7-85 | Full animated view, never referenced |
| `dateLabel` + `todayDateString` | ChoiceView.swift:200-208 | Computed properties, never used in body |
| `formatNumber()` | DailyEnergyCard.swift:206-208 | Private, never called |
| `formatSteps()` | AutomationGuideView.swift:513-524 | Private, never called |
| `saveProfile()` (sync version) | ProfileEditorView.swift:258-267 | Only async version is used |
| `RatingView.swift` | RatingView.swift (entire file) | Placeholder — "Rating will be available soon." |
| Orphaned MARK comment | AppsPageSimplified.swift:684 | `// MARK: - Ticket Shape` with no corresponding code |

### Backend Layer

| Item | File | Notes |
|------|------|-------|
| `normalizeMode()` noop function | admin-panel users/[id]/page.tsx:15-17 | Returns input unchanged — just use `s.mode` directly |
| `clearShield()` | DeviceActivityMonitorExtension.swift:474-477 | Never called |

**Total: 23 dead items remaining (~250 lines removable)**

---

## Remaining Performance Bottlenecks

### PERF-R01: `NumberFormatter` Allocated Per Call (MEDIUM)

**Files:** `CategorySettingsView.swift:286`, `OnboardingStoriesView.swift:613`

Both create a new `NumberFormatter()` on every call. Should use `CachedFormatters` or a static cached instance.

```swift
private func formatNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()  // expensive allocation every call
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}
```

---

### PERF-R02: `trailing7DayKeys` Recomputed Every Body Evaluation (MEDIUM)

**File:** `MeView.swift:96-103`

Creates 7 Date objects and formats them on every SwiftUI body call. Used by `weekRow`, `reflectionLine`, `dimensionRow` — all within the same view body.

**Fix:** Compute once in `.onAppear`/`.task` and store in `@State`.

---

### PERF-R03: `UIImage(named:)` Triple-Fallback in Template Cards (LOW)

**File:** `AppsPageSimplified.swift:811-813`

```swift
let uiImage = UIImage(named: template.imageName)
    ?? UIImage(named: template.imageName.lowercased())
    ?? UIImage(named: template.imageName.capitalized)
```

Tries 3 image name variants on every body evaluation. Should cache the result.

---

### PERF-R04: `supabaseJSONDecoder()`/`Encoder()` Created Per Call (LOW)

**File:** `AuthenticationService.swift:330-339`

Creates new `JSONDecoder`/`JSONEncoder` instances on every call (9 call sites total). Should be lazy properties.

---

### PERF-R05: Per-Row Timer in TicketRowView (LOW)

**File:** `ShieldRowView.swift:90-93`

Each visible ticket row creates its own 1-second `Timer`. With many rows, creates many timers.

**Fix:** Use shared `TimelineView` or parent timer.

---

### PERF-R06: `NSKeyedArchiver.archivedData` in Token Filter Loop (LOW)

**File:** `BlockingStore.swift:258`

Serialization inside a loop over all application tokens during shield rebuild. Scales linearly with number of monitored apps.

---

### PERF-R07: `SupabaseConfig.load()` Called Per Sync Method (LOW)

**File:** `SupabaseSyncService.swift` (multiple locations)

Every sync method reads `Bundle.main.object(forInfoDictionaryKey:)`. While the runtime caches this, loading config once and storing it would be cleaner.

---

### PERF-R08: `resetDailyEnergyState()` Re-runs Migration Logic (LOW)

**File:** `AppModel+DailyEnergy.swift:468-483`

Runs legacy key migration on every day reset even after `energyMigrationVersion` has been bumped. Should check the version flag first.

---

### PERF-R09: Supabase Admin Client Created Per Call (LOW)

**File:** `admin-panel/src/lib/supabaseAdmin.ts`

`supabaseAdmin()` creates a new Supabase client on every function call. Should memoize.

---

### PERF-R10: Large View Files (MAINTAINABILITY)

| File | Lines | Components Contained |
|------|-------|---------------------|
| `AppsPageSimplified.swift` | 1,123 | 5 types — AppsPage, PaperTicketView, RayCapsuleSurface, TemplatePickerView, InlineSettings |
| `MeView.swift` | 1,000 | 10+ types — MeView, SettingsSheet, 4 settings sub-pages, modifiers, helpers |

Should be decomposed for build performance and maintainability.

---

## Remaining State Management Issues

### STATE-R01: `@StateObject` with Singleton (LOW)

**File:** `MeView.swift:6`, `MeView.swift:379` (SettingsSheet)

```swift
@StateObject private var authService = AuthenticationService.shared
```

`@StateObject` implies ownership. For a singleton, `@ObservedObject` is semantically correct (the view doesn't own the lifecycle). In practice, `@StateObject` works fine here — it just prevents re-creation on parent redraws, which is actually desirable. **Cosmetic concern only.**

---

### STATE-R02: Dual-Source Day Boundary (UserDefaults Reads)

Multiple files independently read `dayEndHour_v1` and `dayEndMinute_v1` from UserDefaults:
- `HealthStore.currentDayStart(for:)` — reads from both `.stepsTrader()` and `.standard`
- `Date+Today.swift` — reads only from `.stepsTrader()`
- `DayBoundary.swift` — reads from both
- `UserEconomyStore.clearExpiredDayPasses` — uses `Calendar.current.startOfDay` (ignores custom boundary entirely)

**Fix:** Centralize in `DayBoundary` and have all code use that single path.

---

### STATE-R03: `startTime`/`timer` Not Private

**File:** `AppModel.swift:292-293`

Internal mutable state exposed at `internal` access level. Any file in the module can accidentally mutate them.

---

## Remaining Security Concerns

### SEC-R01: Telegram Webhook Secret Is Optional (MEDIUM)

**File:** `tg-admin/src/index.ts:525-529`

If `TELEGRAM_WEBHOOK_SECRET` env var is not set, the webhook accepts all requests without validation. No runtime warning.

**Fix:** Require the secret or log a prominent warning at startup.

---

### SEC-R02: PostgREST Search Filter Injection (MEDIUM)

**File:** `admin-panel/src/lib/queries.ts:23-27`

User search input is interpolated directly into a PostgREST `or()` filter:

```typescript
q = q.or(`nickname.ilike.%${s}%,email.ilike.%${s}%,id.eq.${s}`);
```

A crafted search term like `%,is_banned.eq.true,nickname.ilike.%` could manipulate the filter.

**Fix:** Escape commas and PostgREST special chars in search input.

---

### SEC-R03: In-Memory Rate Limiting (LOW)

**File:** `admin-panel/src/lib/adminAuth.ts:73-87`

Rate limiter uses an in-memory `Map`. Resets on cold start in serverless environments. Ineffective on Vercel with per-invocation isolation.

**Fix:** Use persistent store (KV, Redis) for production.

---

### SEC-R04: `resolvedFontNames` Static Dict Not Thread-Safe (LOW)

**File:** `Font+Custom.swift:33`

Mutable static `[String: String?]` dictionary accessed without synchronization. Race condition possible if called from multiple threads.

**Fix:** Add `@MainActor` annotation or use `NSLock`.

---

## Duplicate Utility Functions (6 Clusters)

These are copy-pasted implementations that should be consolidated into shared utilities:

### Cluster 1: `formatNumber` — 4 implementations

| File | Line | Approach |
|------|------|----------|
| `CategorySettingsView.swift` | 286 | `NumberFormatter` with grouping |
| `OnboardingStoriesView.swift` | 613 | `NumberFormatter` with grouping |
| `MeView.swift` (SettingsEnergyPage) | 861 | Inline K-suffix |
| `DailyEnergyCard.swift` | 206 | `value < 1000 ? "\(value)" : "\(value / 1000)k"` |

### Cluster 2: `formatTime`/`formatRemaining`/`formatRemainingTime` — 4 implementations

| File | Line |
|------|------|
| `AppsPageSimplified.swift` (PaperTicketView) | 595 |
| `AppsPageSimplified.swift` (InlineTicketSettingsView) | 1107 |
| `ShieldGroupSettingsView.swift` | 432 |
| `ShieldRowView.swift` (TicketRowView) | 104 |

### Cluster 3: `unlockOptionLabel` — 2 implementations

| File | Line |
|------|------|
| `AppsPageSimplified.swift` (InlineTicketSettingsView) | 1115 |
| `ShieldGroupSettingsView.swift` | 443 |

### Cluster 4: `optionTitle(for:)` — 3 implementations

| File | Line |
|------|------|
| `ChoiceView.swift` (GalleryView) | 367 |
| `ChoiceView.swift` (GalleryDayDetailSheet) | 683 |
| `MeView.swift` | 353 |

### Cluster 5: `categoryColor` — 3 implementations

| File | Line |
|------|------|
| `CategorySettingsView.swift` | 241 |
| `CategoryDetailView.swift` | 201 |
| `CustomActivityEditorView.swift` | 28 |

### Cluster 6: `defaultColorHex` — 2 implementations

| File | Line |
|------|------|
| `ColorPaletteView.swift` | 210 |
| `OptionEntrySheet.swift` | 228 |

**Recommendation:** Create `Utilities/FormattingHelpers.swift` with shared `formatNumber(_:)`, `formatRemainingTime(_:)`, `unlockOptionLabel(for:)`. Move `categoryColor(for:)` and `defaultColorHex(for:)` to `EnergyCategory` extensions.

---

## Filename Mismatches

| Current Filename | Actual Contents | Suggested Name |
|------------------|----------------|----------------|
| `ChoiceView.swift` | `GalleryView`, `MetricOverlayKind`, `GalleryShareSheet`, etc. | `GalleryView.swift` |
| `ShieldGroupSettingsView.swift` | `TicketGroupSettingsView` | `TicketGroupSettingsView.swift` |
| `ShieldRowView.swift` | `TicketRowView` | `TicketRowView.swift` |
| `SettingsView.swift` | `enum SettingsView` with only `automationAppsStatic` data | `AutomationAppsData.swift` or merge into `TargetResolver` |

---

## Remaining Difficulty Level References

The main UI (pickers, sliders, badges) has been removed. Residual references:

| Location | Content | Severity |
|----------|---------|----------|
| `Types.swift:118-120` | Comments `// Level III`, `// Level II`, `// Level I` | Cosmetic |
| `Types.swift:126-129` | `Tariff.displayName` returns `"I"`, `"II"`, `"III"`, `"IV"` | Low |
| `AppsPageSimplified.swift:873` | Comment `// Edit settings - reveals difficulty + time intervals` | Cosmetic |
| `admin-panel types.ts:17` | `ShieldRow.level: number` field | Low (DB artifact) |
| `admin-panel users/[id]/page.tsx:201,210` | Renders `level` column in shields table | Low |
| `tg-admin/src/index.ts:490` | Formats as `Lv${s.level}` | Low |
| `admin-panel queries.ts:50` | `listShields` selects `level` | Low |

---

## Optimization Opportunities

### OPT-01: Consolidate Day Boundary Logic (Medium effort, high impact)

Create a single `DayBoundaryProvider` that caches the hour/minute from UserDefaults and is shared across `HealthStore`, `UserEconomyStore`, `Date+Today`, `DayBoundary`, and extensions. Eliminates 5+ duplicate UserDefaults reads and the midnight-vs-custom mismatch in `UserEconomyStore`.

### OPT-02: Extract Shared Formatters (Small effort, medium impact)

Move the 6 duplicate utility clusters into `Utilities/FormattingHelpers.swift`. Add a `NumberFormatter` to `CachedFormatters`. ~100 lines removed, single source of truth.

### OPT-03: Decompose Large Views (Medium effort, long-term impact)

Split `AppsPageSimplified.swift` (1,123 lines) and `MeView.swift` (1,000 lines) into focused files. Improves build times, testability, and code navigation.

### OPT-04: Make `trailing7DayKeys` Stateful (Small effort, medium impact)

Compute once in `.task` and store in `@State`. Eliminates 7 Date allocations + 7 DateFormatter calls per body evaluation in `MeView`.

### OPT-05: Implement `scheduleSupabaseTicketUpsert` (Medium effort, high impact)

The TODO stub means ticket settings changes never sync to Supabase. Route through existing `SupabaseSyncService.syncTicketGroups()`.

### OPT-06: Remove Supabase RPC Fallback (Small effort, cleanup)

Once `sum_energy_delta` RPC is confirmed deployed, remove the client-side pagination fallback code in both `queries.ts` and `tg-admin/src/index.ts`.

### OPT-07: Cache `SupabaseConfig.load()` (Small effort, minor impact)

Load once on service init instead of per-method-call.

### OPT-08: Lazy JSONDecoder/Encoder in AuthenticationService (Small effort, minor impact)

Replace the factory functions with lazy stored properties.

---

## Priority Matrix

### P0 — Fix This Week

| # | Issue | Effort | Impact |
|---|-------|--------|--------|
| 1 | BUG-R01: `clearExpiredDayPasses` uses midnight instead of custom boundary | 15 min | Day passes expire early for custom-boundary users |
| 2 | BUG-R02: HandoffManager defaults unknown apps to Instagram | 15 min | Opens wrong app |
| 3 | BUG-R04: `scheduleSupabaseTicketUpsert` is an empty TODO called 4x | 30 min | Ticket settings never sync |
| 4 | SEC-R02: PostgREST search filter injection | 15 min | Admin panel filter manipulation |

### P1 — Fix Next Sprint

| # | Issue | Effort |
|---|-------|--------|
| 5 | BUG-R03: `applyFamilyControlsSelection` no-op called from UI | 30 min |
| 6 | BUG-R05: `loadDailyTariffSelections` never called, state lost on restart | 15 min |
| 7 | OPT-02: Consolidate 6 duplicate utility clusters | 1 hour |
| 8 | OPT-01: Centralize day boundary logic | 1 hour |
| 9 | PERF-R01: Cache `NumberFormatter` (2 files) | 15 min |
| 10 | PERF-R02: Cache `trailing7DayKeys` in `@State` | 15 min |
| 11 | Delete 23 dead code items (~250 lines) | 1 hour |
| 12 | SEC-R01: Require Telegram webhook secret | 10 min |

### P2 — Backlog

| # | Issue | Effort |
|---|-------|--------|
| 13 | Rename 4 mismatched filenames | 30 min |
| 14 | Clean up 8 residual difficulty level references | 30 min |
| 15 | OPT-03: Decompose `AppsPageSimplified.swift` + `MeView.swift` | 2 hours |
| 16 | BUG-R06: HealthStore 0-step cached data flag | 15 min |
| 17 | BUG-R07: `onOpenURL` handler is a stub | 30 min |
| 18 | PERF-R04: Cache JSONDecoder/Encoder in AuthenticationService | 15 min |
| 19 | PERF-R05: Shared timer for TicketRowView | 30 min |
| 20 | SEC-R03: Persistent rate limiting for admin login | 1 hour |
| 21 | SEC-R04: Thread-safe `resolvedFontNames` | 5 min |
| 22 | OPT-06: Remove Supabase RPC fallback | 15 min |
| 23 | OPT-07: Cache `SupabaseConfig.load()` | 15 min |
| 24 | Add `Sendable` to `NetworkClient` | 5 min |

---

## Score Card: Before vs After

| Category | v1 Audit | v2 Audit | Delta |
|----------|----------|----------|-------|
| Critical bugs | 2 | 0 | -2 |
| High-severity bugs | 3 | 2 | -1 |
| Medium-severity bugs | 7 | 4 | -3 |
| Security issues (Critical/High) | 3 | 0 | -3 |
| Security issues (Medium) | 2 | 2 | 0 |
| Dead code items | 40+ | 23 | -17+ |
| Performance bottlenecks (High) | 3 | 0 | -3 |
| Performance bottlenecks (Med/Low) | 9 | 10 | +1 |
| Duplicate utility clusters | ~5 | 6 | +1 (better counted) |

**Overall: Critical and high-severity issues are largely resolved. Remaining work is mostly cleanup (dead code, duplicates, filenames) and two medium-impact bugs (day boundary mismatch, empty Supabase sync stub).**

---

*End of v2 audit. Total files re-analyzed: 107 Swift, 17 TypeScript/TSX, 2 Metal, 4 extensions, all backend services.*
