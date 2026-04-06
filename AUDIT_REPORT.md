# Full App Audit Report — Steps4 (Nowhere)

**Date:** April 4, 2026
**Scope:** All 135 Swift files across 7 targets — main app, 4 extensions, tests, widget
**Product:** Nowhere.app (Steps4 Xcode project)
**Reviewers:** 3 independent senior engineers (Architecture, UI/UX, Security/Quality)
**Total findings:** 128 (3 P0, 26 P1, 65 P2, 34 P3)

---

## Table of Contents

1. [Critical Bugs (P0)](#1-critical-bugs-p0)
2. [High-Priority Bugs (P1)](#2-high-priority-bugs-p1)
3. [Architecture & Design Issues](#3-architecture--design-issues)
4. [State Management & Concurrency](#4-state-management--concurrency)
5. [Security Vulnerabilities](#5-security-vulnerabilities)
6. [UI/UX & Accessibility](#6-uiux--accessibility)
7. [Extension & Widget Issues](#7-extension--widget-issues)
8. [Error Handling](#8-error-handling)
9. [Dead Code](#9-dead-code)
10. [Code Duplication](#10-code-duplication)
11. [Hardcoded Values & Magic Numbers](#11-hardcoded-values--magic-numbers)
12. [Performance](#12-performance)
13. [Test Coverage](#13-test-coverage)
14. [Localization & Dark Mode](#14-localization--dark-mode)
15. [HIG Compliance](#15-hig-compliance)
16. [Privacy & App Transport](#16-privacy--app-transport)
17. [Summary Checklist](#17-summary-checklist)

---

## 1. Critical Bugs (P0)

### 1.1 Supabase Anon Key in Plaintext Binary
- **File:** `Config/Secrets.xcconfig`
- **Impact:** The Supabase URL and anon key are hardcoded in plaintext. Though `.gitignore`d, values are baked into `Info.plist` at build time and ship in the binary. Anyone can extract them with `strings` or `plutil`. If this key leaks via IPA extraction, anyone can call your Supabase REST/Auth endpoints.
- **Fix:** Rely on RLS server-side. Rotate the key periodically. Consider obfuscating at build time (XOR with compile-time constant). Verify it was never committed: `git log --all -- Config/Secrets.xcconfig`.

### 1.2 `HandoffManager.attemptOpenScheme` — MainActor Isolation Violation
- **File:** `HandoffManager.swift:73`
- **Impact:** `UIApplication.shared.open(url)` completion handler fires on an arbitrary thread, but recursively calls `self?.attemptOpenScheme` which is `@MainActor`-isolated. Data race — the Swift concurrency runtime may crash or produce undefined behavior.
- **Fix:** Wrap the recursive call in `Task { @MainActor in self?.attemptOpenScheme(...) }` inside the completion closure.

### 1.3 `handlePayGatePaymentForGroup` — Accounting Drift
- **File:** `AppModel+PayGate.swift:100`
- **Impact:** `addSpentSteps(cost, for: "group_\(groupId)")` is called after `pay(cost:)` already deducted from `spentStepsToday`. But `pay()` increments `spentStepsToday` by `consumeFromBase` (which may be less than `cost` if bonus steps absorb the rest), while `addSpentSteps` records the full `cost`. Over time per-app spent totals will exceed base-energy spent — silent accounting drift.
- **Fix:** In `addSpentSteps`, only track the per-app dictionary. Document that `spentStepsToday` and per-app tracking measure different things, or unify the accounting path.

---

## 2. High-Priority Bugs (P1)

### 2.1 `resetDailyEnergyState` Ordering Fragility
- **File:** `AppModel+DailyEnergy.swift:349-430`
- **Impact:** Reads persisted selection arrays, computes `inkEarned`, saves snapshot, then clears in-memory state. If `loadDailyEnergyState` was never called (first launch), arrays are empty. The method reads `SharedKeys.spentStepsToday` which may belong to the new day if `checkDayBoundary` ran first. Ordering is fragile — data can be silently lost.
- **Fix:** Extract snapshot building into a pure function with explicit parameters. Ensure `checkDayBoundary` → `resetDailyEnergyState` always reads the old anchor before state is modified for the new day.

### 2.2 `CanvasStorageService` — Lazy Var Thread Unsafety
- **File:** `CanvasStorageService.swift:19,38`
- **Impact:** `storageDirectory` and `snapshotDirectory` are `lazy var` on a non-`Sendable`, non-`@MainActor` class. If `saveCanvas` and `loadCanvas` are called from different threads, lazy initialization races.
- **Fix:** Make `CanvasStorageService` an actor, or make these `let` constants initialized in `init`.

### 2.3 `NotificationDelegate` — Weak Reference Race
- **File:** `NotificationDelegate.swift:9`
- **Impact:** `weak var model: AppModel?` is accessed via `Task { @MainActor in self.model?... }` from delegate callbacks on arbitrary threads. The property read crosses isolation boundaries — data race on the weak reference.
- **Fix:** Make `NotificationDelegate` `@MainActor` or use `nonisolated(unsafe)` with explicit `MainActor.assumeIsolated`.

### 2.4 `recalculateDailyEnergy` — Excessive I/O Per Step Update
- **File:** `AppModel+DailyEnergy.swift:790-847`
- **Impact:** Called on every step update (via Combine debounce, 200ms), every selection toggle, every foreground resume. Each call triggers: `writeWidgetSnapshot()` (JSON encode + file write), `WidgetCenter.shared.reloadAllTimelines()`, Supabase `syncDailyStats`, and `syncUserPreferencesToSupabase`. Excessive main-thread I/O.
- **Fix:** Debounce `writeWidgetSnapshot` and `reloadAllTimelines` to at most once per second. Move `syncUserPreferencesToSupabase` out — it should only sync when preferences actually change.

### 2.5 `findTicketGroup(for:)` — O(G×T) Serialization Hot Path
- **File:** `AppModel+TicketGroups.swift:64-97`
- **Impact:** For each call: iterates ALL ticket groups, for each group iterates ALL `applicationTokens`, calling `NSKeyedArchiver.archivedData(withRootObject:)` + `base64EncodedString()` for every token. Called from `unlockSettings(for:)` which is called from payment flows and UI rendering.
- **Fix:** Build and cache a `[String: TicketGroup]` lookup table (bundle ID → group) once after `loadTicketGroups` and invalidate on group mutations.

### 2.6 Widget Intent Double-Spend Race
- **File:** `UnlockGroupWidgetIntent.swift:39-111`
- **Impact:** Widget `perform()` modifies shared UserDefaults without any locking. Reads `stepsBalance`, computes new values, writes back. If main app or another intent fires simultaneously — classic read-modify-write race. Two rapid taps could double-spend.
- **Fix:** Use `NSFileCoordinator` for atomic read-modify-write, or add debounce (like `ShieldActionExtension` line 42-48). Currently no debounce in the widget intent.

### 2.7 `pendingContinuations` Potential Hang
- **File:** `AuthenticationService.swift:95-120`
- **Impact:** `waitForInitialization()` uses `withCheckedContinuation`. If two callers enter simultaneously and `isInitialized` becomes `true` between the check and the append, the continuation is appended after `init()` drained the array — **leaked continuation**, caller hangs forever.
- **Fix:** Use `AsyncStream` or explicit state machine. The double-check helps but doesn't fully prevent the race within the same MainActor turn.

### 2.8 Extension Memory Pressure — Double Group Iteration
- **File:** `DeviceActivityMonitorExtension.swift:155-305`
- **Impact:** `setupBlockForMinuteMode()` loads and iterates all ticket groups with JSON + `NSKeyedArchiver` decoding (lines 166-196), then loads and iterates again (lines 236-258) to resolve a bundle ID. Extensions get ~6MB memory; this is O(n²) in decoding for many groups.
- **Fix:** Collect all needed data in a single pass. Store `firstApp` → `groupId` mapping during the first iteration.

### 2.9 `GalleryView` Safe Area Insets — Stale and Wrong on SE
- **File:** `GalleryView.swift:68-76`
- **Impact:** `deviceTopInset`/`deviceBottomInset` access `UIApplication.shared.connectedScenes` from a computed property on a View struct — main-actor violation on iOS 17+. Insets become stale on rotation/in-call bar changes. Fallback values (59, 34) are wrong for iPhone SE (top inset = 20).
- **Fix:** Use `GeometryReader` with `safeAreaInsets` or pass insets through environment.

### 2.10 `contentShape(Circle().size())` Hit Area Bug
- **File:** `GalleryView.swift:369, 431`
- **Impact:** `Circle().size(width: 72, height: 72)` creates a shape at (0,0) not centered on the button — hit area is offset. Buttons may not respond to taps in the expected area.
- **Fix:** Use `.contentShape(Circle())` without `.size()`, or use `.frame(width: 72, height: 72).contentShape(Circle())`.

### 2.11 `canonicalPortraitSize` Computed Once at Launch
- **File:** `GalleryView.swift:130-153`
- **Impact:** Canvas layers use `GenerativeCanvasView.canonicalPortraitSize` computed once from `UIScreen.main.bounds` at launch. If the app launches in landscape or on iPad split view, the canvas size is permanently wrong.
- **Fix:** Compute from `GeometryReader` or re-evaluate on size class change.

### 2.12 Accessibility Labels Missing on Interactive Elements
- **File:** `RadialHoldMenu.swift:120-157`, `GalleryView.swift:352-436`, `MeView.swift:247`
- **Impact:** Fan-open category nodes (Body/Mind/Heart) have no accessibility labels. Share and label-toggle buttons in GalleryView have no labels. Interactive pills in MeView lack hints. VoiceOver users cannot navigate these elements.
- **Fix:** Add `.accessibilityLabel()` to each interactive element. Add `.accessibilityHint("Double tap to change")` on tappable pills.

### 2.13 Hardcoded Locale `"en"` in Title Lookups
- **File:** `CategoryDetailView.swift:197`, `GalleryView.swift:1221-1224`
- **Impact:** `option.title(for: "en")` — hardcoded to English locale. On non-English devices, always shows English titles for built-in options.
- **Fix:** Use `Locale.current.language.languageCode?.identifier ?? "en"`.

### 2.14 Keychain Migration — Silent Session Loss
- **File:** `AuthenticationService.swift:397-413`
- **Impact:** If `saveSession` to Keychain fails (disk full, keychain corruption), the code deletes from UserDefaults but the session is lost. User is silently logged out.
- **Fix:** Check return value of `SessionKeychain.saveSession()` before removing from UserDefaults.

### 2.15 App Group Defaults Silent Fallback
- **File:** `SharedKeys.swift:44-45`
- **Impact:** `SharedKeys.appGroupDefaults()` silently falls back to `.standard` without logging. Extensions calling this get `.standard` if the container fails — their writes are invisible to the main app. ShieldRebuildHelper, DeviceActivityMonitor, and ShieldAction all use this.
- **Fix:** At minimum log a warning. Better: crash in debug (like `UserDefaults.stepsTrader()` does with `assertionFailure`).

### 2.16 Launch UI Test Asserts Nothing
- **File:** `Steps4UITests/Steps4UITestsLaunchTests.swift:1-17`
- **Impact:** Launch test calls `app.launch()` but has no assertions. No-op placeholder that gives false confidence in the UI test suite.
- **Fix:** Add meaningful assertions (screenshot comparison, check for known UI element) or delete.

### 2.17 Zero Test Coverage on Security-Critical Code
- **File:** `Steps4Tests/` (all)
- **Impact:** `AuthenticationService`, `SessionKeychain`, `SupabaseSyncService`, `ShieldRebuildHelper`, `UnlockGroupWidgetIntent` have zero test coverage. The authentication flow, token refresh, session storage, and shield rebuild logic are entirely untested.
- **Fix:** Add unit tests for `SessionKeychain` save/load/delete, `ensureValidSession`, `ShieldRebuildHelper.rebuild()`, `UnlockGroupWidgetIntent.perform()` balance math.

### 2.18 Singleton DI Bypass Throughout Extensions
- **File:** `AppModel.swift:26`, all extensions
- **Impact:** `AuthenticationService.shared`, `SupabaseSyncService.shared`, `CanvasStorageService.shared`, `ErrorManager.shared`, `CloudKitService.shared` — all hard singletons accessed directly, bypassing `DIContainer`. Makes the code untestable and tightly coupled.
- **Fix:** Inject through `DIContainer` and pass as init parameters. Create a `SyncCoordinator` protocol that AppModel receives.

### 2.19 `PaperTicketView` Timer Leak
- **File:** `PaperTicketView.swift:24`
- **Impact:** `Timer.publish(every: 15)` as a `let` on a struct creates a new publisher every time the parent redraws. Old subscriptions may linger, creating timer leaks.
- **Fix:** Move timer to `@State` or use a view model.

### 2.20 `fetchResistanceUsers` Uses Anon Key Without Auth
- **File:** `AuthenticationService.swift:746-776`
- **Impact:** Request sends only `apikey` with no `Authorization: Bearer` header. Runs with anon-level RLS, potentially exposing more user data than intended. Any client can enumerate nicknames + UUIDs.
- **Fix:** Add `Bearer \(session.accessToken)` to headers, or lock down RLS policy on `public.users`.

---

## 3. Architecture & Design Issues

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 3.1 | P1 | `AppModel.swift` + 13 extensions | **God object.** 30+ forwarding computed properties (lines 54-148), business logic across 13 extensions (~2000+ LOC combined). Every extension directly mutates stores and calls `SupabaseSyncService.shared`. | Eliminate forwarding properties — views access stores directly via `model.healthStore.stepsToday`. Move sync into a `SyncCoordinator`. |
| 3.2 | P2 | `AuthenticationService.swift` (994 lines) | Combines auth flow, profile management, avatar disk I/O, user fetching, resistance listing, nonce generation, Keychain helpers, and 6 DTOs. | Split: `AuthService` (auth + session), `ProfileService` (profile + avatar), DTOs to own file. |
| 3.3 | P2 | `CloudKitService.swift` + `SupabaseSyncService.swift` | Two parallel sync backends. `CloudKitService` is functional. No conflict resolution between the two. | Deprecate CloudKitService if Supabase is source of truth. |
| 3.4 | P2 | `ShieldRebuildHelper` + `BlockingStore` | Both iterate ticket groups and union `FamilyActivitySelection` tokens. Can produce different results. | Consolidate into one rebuild path — `BlockingStore` delegates to `ShieldRebuildHelper`. |
| 3.5 | P2 | `DIContainer.swift` | Only injects 4 of ~10+ services. Creates concrete types directly with no protocol abstraction. | Add factory methods for all services. Support `makeTestContainer()`. |
| 3.6 | P2 | `UserEconomyStore.swift:8` | `private let persistence = PersistenceManager.shared` — hard singleton, untestable. | Accept `PersistenceManager` as init parameter. |

---

## 4. State Management & Concurrency

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 4.1 | P2 | `AppModel.swift:36` | `nonisolated static func storedDayEnd()` reads UserDefaults outside `@MainActor` isolation. | Mark `@MainActor` or document the intentional break. Same for `dayKey(for:)` at line 47. |
| 4.2 | P2 | `SupabaseSyncService.swift:43` | `todayCacheTTL` reads UserDefaults from an actor context. Multiple properties do this. | Cache config values at init time instead of reading per-call. |
| 4.3 | P2 | `AppModel.swift:309` | `Timer.scheduledTimer` callback captures `[weak self]` twice — once for Timer closure, once for inner Task. | Simplify: use Timer directly from MainActor context, single capture. |
| 4.4 | P2 | `UserEconomyStore.swift:23-36` | `stepsBalance`/`spentSteps` `didSet` triggers synchronous UserDefaults write on every mutation. During `recalculateDailyEnergy` this creates bursts of I/O on main thread. | Batch writes with `setNeedsFlush()` pattern — coalesce into single `RunLoop.main.perform`. |
| 4.5 | P2 | `SupabaseSyncService.swift:186-188` | Cross-actor UserDefaults write. Fire-and-forget `Task` to `@MainActor`. Rapid successive calls can interleave and clobber. | Serialize writes within the actor or await the `@MainActor` continuation. |
| 4.6 | P3 | `NetworkClient.swift:5` | `NetworkClient` marked `Sendable` but holds `URLSession` — fragile if state added later. | Add `@unchecked Sendable` explicitly to signal intent. |

---

## 5. Security Vulnerabilities

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 5.1 | P1 | `AuthenticationService.swift:648` | Sensitive data logged in debug builds — full PATCH response bodies, user IDs, session expiry. If debug logging ships or logs are collected, this leaks PII. | Gate `AppLogger.auth.debug` behind `#if DEBUG`. Redact user IDs in logs. |
| 5.2 | P2 | `AuthenticationService.swift:222-293` | No input validation on `nickname` or `country` before sending to Supabase. Arbitrary strings (XSS payloads, SQL-like) submitted as nickname, displayed to other users. | Validate: max length, character whitelist for nickname; ISO 3166 for country. |
| 5.3 | P2 | `UnlockGroupWidgetIntent.swift:89-91` | Undeclared UserDefaults keys `"pendingSpendAmount_\(groupId)"` and `"pendingSpendTracking_\(groupId)"` — not in `SharedKeys`. | Move to `SharedKeys` with proper naming. |
| 5.4 | P3 | `AuthenticationService.swift:309-311` | Force-unwrap on `FileManager.default.urls(for: .documentDirectory, ...)` — safe in practice but code smell in security code. | Use `guard let`. |
| 5.5 | P3 | Keychain | `SessionKeychain` well-implemented with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Consider adding `kSecAttrSynchronizable: false` explicitly. | Add explicit flag and log `saveSession` failures. |

---

## 6. UI/UX & Accessibility

### Touch Targets Below 44pt Minimum

| File | Element | Size | Fix |
|------|---------|------|-----|
| `RadialHoldMenu.swift:120-157` | Category fan nodes | 40×40 | Increase to 44×44 |
| `MeView.swift` (MeTargetsSheet L651) | Stepper minus/plus | 30×30 | Increase to 44×44 |
| `WorkoutSuggestionBanner.swift:77` | Dismiss "xmark" | 24×24 | Add `.frame(minWidth: 44, minHeight: 44)` |

### Missing Accessibility Labels

| File | Element | Fix |
|------|---------|-----|
| `RadialHoldMenu.swift` | Category nodes (Body/Mind/Heart) | Add `.accessibilityLabel()` per node |
| `GalleryView.swift:352-436` | Share and label-toggle buttons | Add `.accessibilityLabel("Share canvas")` etc. |
| `MeView.swift:247` | Interactive value pills | Add `.accessibilityHint("Double tap to change")` |
| `CategoryDetailView.swift:173` | Activity rows | Combine title + selected state in label |
| `ManualsPage.swift:68-99` | Note cards | Add `.accessibilityElement(children: .combine)` |
| `StepBalanceCard.swift:65-119` | Header pill complex | Wrap in `accessibilityElement(children: .ignore)` with combined label |

### Dynamic Type Issues

| File | Issue | Fix |
|------|-------|-----|
| `MeView.swift:106-116` | `meProse` / `meNumberProse` use hardcoded `Font.system(size:)` | Use `.body` or at minimum add `.dynamicTypeSize(...)` |
| `OnboardingStoriesView.swift:283-292` | CTA button uses `font(.systemSerif(18))` hardcoded | Use `relativeTo:` parameter |

### Layout Issues

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 6.1 | P2 | `GalleryView.swift:1064` | Export hardcoded `.frame(width: 390, height: 500)` — wrong on non-390pt devices | Use `canonicalPortraitSize` or proportional |
| 6.2 | P2 | `OnboardingStoriesView.swift:695` | Paint demo canvas hardcoded 280×280 — overlaps on SE | Use `GeometryReader` for proportional size |
| 6.3 | P3 | `HandoffProtectionView.swift:75` | `.padding(.horizontal, 40)` — buttons clip on SE with long text | Stack buttons vertically on narrow screens |

---

## 7. Extension & Widget Issues

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 7.1 | P2 | `DeviceActivityMonitorExtension.swift:60-85` | `storeErrorLog` reads, decodes, appends, encodes, writes JSON on every error. In a tight error loop this exhausts extension memory/time. | Rate-limit: max 1 write per 5s, or append-only format. |
| 7.2 | P2 | `ShieldConfigurationExtension.swift:66-74` | `NSKeyedArchiver.archivedData` runs every time shield UI is displayed. Allocations are significant. | Cache base64 token strings when shield is first applied. |
| 7.3 | P2 | `UnlockTimelineProvider.swift:127,396` | Side-effect writes (`hasLargeWidget`/`hasMediumWidget`) during timeline generation. Can cause unnecessary widget reloads. | Move to `handleAppDidEnterBackground()` or one-time migration. |
| 7.4 | P3 | `DeviceActivityMonitor.entitlements:6-8` | `com.apple.developer.applesignin` present — extension doesn't do Apple Sign-In. | Remove unnecessary entitlement. |
| 7.5 | P3 | `UnlockTimelineProvider.swift:316-331` | `loadWallpaperBackground()` loads full JPEG during timeline generation. Widget extensions have ~30MB limit. | Downscale to widget dimensions before loading. |
| 7.6 | P2 | Widget entitlements | Widget extension may be missing `com.apple.developer.family-controls` — calls `ShieldRebuildHelper.rebuild()` which uses `ManagedSettingsStore`. | Verify widget can apply shields; if not, remove the rebuild call. |

---

## 8. Error Handling

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 8.1 | P1 | `AppModel+DailyEnergy.swift:87,295,478` | Pervasive `try?` for JSONEncoder/Decoder. If encoding fails (corrupt `FamilyActivitySelection`), selections silently lost. | Use `do/catch` with `AppLogger` for critical data. |
| 8.2 | P2 | `BlockingStore.swift:127-128` | `try? JSONEncoder().encode(ticketGroups)` — encoding failure means user's ticket config is not persisted, but in-memory state changed. Next launch loads stale data. | `do/catch`, log error, optionally revert in-memory state. |
| 8.3 | P2 | `AppModel+AppSelection.swift:15` | `saveAppSelection` logs to debug on failure — core FamilyControls selection loss means shield won't work after restart. | Escalate to `ErrorManager.shared.handle()`. |
| 8.4 | P3 | `SupabaseSyncService.swift:186-188` | `saveRetryQueue` via fire-and-forget Task — if process terminates before Task executes, queue is lost. | Write synchronously — it's a small JSON blob. |

---

## 9. Dead Code

### Entire Files

| File | Lines | Reason |
|------|-------|--------|
| `CloudKitService.swift` | ~313 | Fully superseded by `SupabaseSyncService`. Still instantiated as singleton. |
| `LocationPermissionRequester.swift` | ~17 | Trivially wraps `CLLocationManager.requestWhenInUseAuthorization()`. `ProfileLocationManager` handles all actual logic. |

### Dead Functions & Properties

| Symbol | File | Issue |
|--------|------|-------|
| `BudgetEngine.consume(mins:)` | `BudgetEngine.swift` | Never called from AppModel or any view |
| `BudgetEngine.remainingMinutes` | `BudgetEngine.swift` | Never read outside BudgetEngine |
| `BudgetEngine.dailyBudgetMinutes` | `BudgetEngine.swift` | Legacy, unused |
| `loadAppSelection()` | `AppModel+AppSelection.swift:24` | Defined but never called during bootstrap or anywhere |
| `Tariff.entryCostSteps`, `Tariff.stepsPerMinute` | `Types.swift` | Actual entry costs come from `TicketGroup.cost(for:)` |
| `OptionEntrySheet` | `OptionEntrySheet.swift` | Never instantiated — `CategoryDetailView` has its own inline editor |
| `ColorPaletteView` | `ColorPaletteView.swift` | Never instantiated — inline color grids used elsewhere |
| `QuickStatusView` | `QuickStatusView.swift` | `#if DEBUG` only — never visible to end users, hardcoded English |

### Dead UI State

| Symbol | File | Issue |
|--------|------|-------|
| `showSaveRoutine` flow | `GalleryView.swift:43` | Only reachable via deeply nested context menu — unlikely discoverable |
| `GalleryView dayCanvas` init | `GalleryView.swift:34` | `Date()` called at struct init time, may be wrong if view created before midnight |

---

## 10. Code Duplication

| # | Sev | Pattern | Files | Fix |
|---|-----|---------|-------|-----|
| 10.1 | P2 | Day-end hour/minute loaded from UserDefaults in 4+ places with identical fallback | `AppModel.storedDayEnd()` / `DayBoundary.storedDayEnd()` / `BudgetEngine.init()` / `HealthStore.currentDayStart()` | Single `DayBoundary.storedDayEnd()` used everywhere |
| 10.2 | P2 | "Load from file, fall back to UserDefaults, migrate" pattern | `AppModel+DailyEnergy.swift:302` / `UserEconomyStore.loadFromPersistenceOrDefaults` | Extract generic `MigratingStore<T: Codable>` |
| 10.3 | P3 | Preferences payload built identically in two places | `syncUserPreferencesToSupabase()` / `performFullSync` | Extract `UserPreferencesSnapshot.current()` factory |
| 10.4 | P2 | `ShieldRebuildHelper.rebuild()` decodes every group's `FamilyActivitySelection` on every call — main app, monitor extension, and widget all duplicate this work | `ShieldRebuildHelper.swift:114-165` | Cache decoded selections keyed by group ID, invalidate on data change |

---

## 11. Hardcoded Values & Magic Numbers

| File | Value | Fix |
|------|-------|-----|
| `TicketGroup.swift:26-28` | `baseCosts = [.minutes10: 4, .minutes30: 10, .hour1: 20]` — core economy | Move to `PricingConfig` with remote config |
| `HandoffToken.isExpired` | 60s | `AppConstants.Timing` namespace |
| `payGateDismissedUntil` | 10s | `AppConstants.Timing` |
| Sleep refetch delay | 60s | `AppConstants.Timing` |
| `cleanupTimer` | 30s | `AppConstants.Timing` |
| `NotificationManager` | `timeInterval: 0.1` in 6+ places | Use `timeInterval: 1` — Apple docs recommend ≥1s for non-repeating |
| `EnergyDefaults.sleepTargetHours` | `8` | Document rationale |
| `EnergyDefaults.stepsTarget` | `10_000` | Document rationale |

---

## 12. Performance

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 12.1 | P1 | `AppModel+DailyEnergy.swift` | `recalculateDailyEnergy` triggers widget rewrite + Supabase sync on every step update, selection toggle, foreground resume | Debounce to 1s. Sync preferences only when they change. |
| 12.2 | P1 | `AppModel+TicketGroups.swift:64-97` | `findTicketGroup` does O(G×T) `NSKeyedArchiver` serialization per call | Cache lookup table |
| 12.3 | P2 | `UserEconomyStore.swift:23-36` | Synchronous `UserDefaults.set()` on every `didSet` — burst of I/O during recalculation | Batch writes |
| 12.4 | P2 | `GalleryView.swift:84-95` | `canvasSyncTrigger` array reconstructed on every body evaluation. `onChange` fires on every model change regardless of canvas relevance. | Use `Equatable` checks on specific properties. |
| 12.5 | P2 | `OnboardingStoriesView.swift:387-434` | Multiple `DispatchQueue.main.asyncAfter` calls (up to 4 per slide) capturing state. If user navigates away, closures execute against stale state. | Replace with cancellable `Task { try await Task.sleep(...) }`. |
| 12.6 | P2 | `ShieldRebuildHelper.swift:114-165` | `rebuild()` decodes every group's `FamilyActivitySelection` on every call. Extensions have tight memory limits. | Cache decoded selections. |
| 12.7 | P3 | `GenerativeCanvasView.swift:131-133` | `tintedImageCache` is static `[String: Image]` with 400-entry limit and bulk-clear only — no LRU, never shrinks. | Use `NSCache` for auto memory-pressure response. |
| 12.8 | P3 | `UnlockTimelineProvider.swift:154-230` | `buildEntry()` does multiple JSON decode operations per timeline entry. | Pre-decode and cache at start of `timeline(for:in:)`. |

---

## 13. Test Coverage

### Critical Gaps

| Area | Status | Risk |
|------|--------|------|
| `AuthenticationService` + `SessionKeychain` | Zero tests | Auth flow, token refresh, session persistence untested |
| `ShieldRebuildHelper.rebuild()` | Zero tests | Shield logic untested |
| `UnlockGroupWidgetIntent.perform()` | Zero tests | Balance math in widget untested |
| `SupabaseSyncService` (all extensions) | Zero tests | Entire sync layer untested |
| Widget timeline providers | Zero tests | Timeline generation untested |
| Extension entry points | Zero tests | DeviceActivityMonitor, ShieldAction, ShieldConfig untested |

### Test Quality Issues

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 13.1 | P2 | `BudgetEngineTests.swift:17-28` | Tests use `UserDefaults.standard` directly, not App Group container. Could pass even if real code is broken. | Use dedicated `UserDefaults(suiteName: "test-\(UUID())")` per test, injected into `BudgetEngine`. |
| 13.2 | P2 | `DayBoundaryTests.swift` | All tests use `TimeZone(secondsFromGMT: 0)` only. DST transitions untested — where boundary bugs hide. | Add tests with `America/New_York`, `Europe/Berlin`, especially around DST. |
| 13.3 | P2 | `SharedMocks.swift:5-15` | `MockHealthKitService` returns hardcoded zeros. Tests never exercise HealthKit data paths. | Use `ConfigurableHealthKitMock` from `HealthKitTests.swift` everywhere. |
| 13.4 | P3 | All tests | No negative/adversarial tests. No verification when UserDefaults returns corrupt data, JSON decoding fails, or App Group is unavailable. | Add fuzz tests for `ShieldRebuildHelper.loadGroups` with malformed JSON, widget intent with negative balances. |

---

## 14. Localization & Dark Mode

### Localization Issues

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 14.1 | P1 | `CategoryDetailView.swift:197` | `option.title(for: "en")` hardcoded English | Use `Locale.current.language.languageCode?.identifier ?? "en"` |
| 14.2 | P1 | `GalleryView.swift:1221-1224` | Same — `option.title(for: "en")` and `customOptionTitle(for: id, lang: "en")` | Use device locale |
| 14.3 | P2 | `PaperTicketView.swift:248` | Manual pluralization: `\(appsCount == 1 ? "app" : "apps")` — fails for languages with complex plural rules (Russian has 3 forms) | Use `.xcstrings` plural rules |
| 14.4 | P1 | `QuickStatusView.swift:17-63` | All strings hardcoded English | Wrap in `String(localized:)` |

### Dark Mode Issues

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 14.5 | P2 | `StepBalanceCard.swift:264-272` | `Color(white: 0.10)` hardcoded — relies on energy gradient behind it. Contrast may be poor in light mode. | Use theme `backgroundSecondary` or check `colorScheme`. |
| 14.6 | P2 | `PaperTicketView.swift:68-75` | `.foregroundStyle(.black)` hardcoded — correct on yellow/white cards but fragile. | Use `Color(.label)` or computed contrast color. |

---

## 15. HIG Compliance

| # | Sev | File | Issue | Fix |
|---|-----|------|-------|-----|
| 15.1 | P2 | All Settings pages | Custom back button + hidden system nav bar. Breaks standard back gesture visual feedback. | Use system nav bar with custom appearance. |
| 15.2 | P2 | `MainTabView.swift:294-395` | Custom tab bar replaces system tab bar entirely. No system haptics, no long-press customization (iOS 18+), no auto-hiding in scroll views. | Consider system TabView with customization. |
| 15.3 | P2 | `PayGateView.swift` | Full-screen blocking modal with no close/X button. Only "keep it closed" or unlock buttons. No escape hatch. | Add close/X button in top corner per HIG. |
| 15.4 | P3 | `LoginView.swift:62-64` | `SignInWithAppleButton` clipped to custom `RoundedRectangle(cornerRadius: 14)`. Apple HIG recommends using built-in corner radius. May cause App Review rejection. | Remove custom `clipShape`, use button's default shape. |

---

## 16. Privacy & App Transport

### Privacy Manifest

| # | Sev | Issue | Fix |
|---|-----|-------|-----|
| 16.1 | P2 | `PrivacyInfo.xcprivacy` only declares `UserDefaults` with reason `CA92.1`. App also uses HealthKit, FileManager, Keychain, NSKeyedArchiver. | Audit all Required Reason APIs against Apple's list. Ensure manifest is complete. |
| 16.2 | P3 | `NSPrivacyTracking` is `false`. App sends activity data, sleep hours, steps, nicknames, daily selections to Supabase. | Verify no third-party SDK performs tracking. If analytics go beyond your own Supabase, set `true` and implement ATT. |

### App Transport Security

No `NSAppTransportSecurity` exceptions found. All network calls go to `supabase.co` over HTTPS. ATS enforced by default. **No action needed.**

---

## 17. Summary Checklist

### Critical (P0) — Fix Immediately
- [ ] Rotate Supabase anon key. Verify never committed to git history. Ensure RLS policies are airtight.
- [ ] Fix `HandoffManager.attemptOpenScheme` MainActor isolation violation — potential crash.
- [ ] Fix `handlePayGatePaymentForGroup` accounting drift between `spentStepsToday` and per-app tracking.

### High Priority (P1) — Fix This Sprint

**Bugs & Crashes**
- [ ] Fix `resetDailyEnergyState` ordering fragility — snapshot may read wrong day's data.
- [ ] Fix `CanvasStorageService` lazy var thread unsafety — make actor or eager init.
- [ ] Fix `NotificationDelegate` weak reference race across isolation.
- [ ] Fix widget intent double-spend race — add debounce or atomic writes.
- [ ] Fix `pendingContinuations` potential hang in AuthenticationService.
- [ ] Fix Keychain migration — check `saveSession` return before deleting UserDefaults.
- [ ] Fix App Group defaults silent fallback in `SharedKeys`.

**Performance**
- [ ] Debounce `recalculateDailyEnergy` side-effects (widget rewrite, Supabase sync).
- [ ] Cache `findTicketGroup` lookup table — eliminate O(G×T) NSKeyedArchiver serialization.
- [ ] Consolidate extension double-iteration in `setupBlockForMinuteMode`.

**UI/UX**
- [ ] Fix `GalleryView` safe area insets — use GeometryReader, not stale UIApplication query.
- [ ] Fix `contentShape(Circle().size())` hit area bug.
- [ ] Fix `canonicalPortraitSize` computed once — breaks on iPad/landscape launch.
- [ ] Add accessibility labels to RadialHoldMenu, GalleryView buttons, MeView pills.
- [ ] Fix hardcoded locale `"en"` in title lookups.

**Security**
- [ ] Gate debug logging behind `#if DEBUG` in AuthenticationService.
- [ ] Add auth token to `fetchResistanceUsers` request.

**Architecture**
- [ ] Inject singletons through DIContainer instead of accessing `.shared` directly.

**Tests**
- [ ] Add tests for AuthenticationService, SessionKeychain, ShieldRebuildHelper, widget intent.
- [ ] Fix launch UI test — add assertions or delete.

### Medium Priority (P2) — Next 2 Sprints

**Architecture**
- [ ] Split `AuthenticationService` into auth + profile services.
- [ ] Deprecate/remove `CloudKitService` if Supabase is source of truth.
- [ ] Consolidate `ShieldRebuildHelper` + `BlockingStore` rebuild paths.
- [ ] Add protocol-based DI to `DIContainer` — support test configuration.
- [ ] Inject `PersistenceManager` into `UserEconomyStore`.

**Concurrency**
- [ ] Make `AppModel.storedDayEnd()` / `dayKey(for:)` `@MainActor`.
- [ ] Cache SupabaseSyncService config values at init.
- [ ] Serialize `saveRetryQueue` writes within actor.
- [ ] Batch `UserEconomyStore` didSet writes.

**Security**
- [ ] Validate `nickname` / `country` input before Supabase.
- [ ] Move undeclared widget UserDefaults keys to `SharedKeys`.

**Extensions**
- [ ] Rate-limit `storeErrorLog` in DeviceActivityMonitor.
- [ ] Cache NSKeyedArchiver results in ShieldConfigurationExtension.
- [ ] Remove side-effect writes from timeline provider.
- [ ] Verify widget entitlements for FamilyControls.

**Error Handling**
- [ ] Replace `try?` with `do/catch + logging` in DailyEnergy encode/decode.
- [ ] Fix `BlockingStore` silent encode failure — log and revert.
- [ ] Escalate `saveAppSelection` failure to visible error.

**UI/UX**
- [ ] Fix export hardcoded size (390×500).
- [ ] Fix paint demo canvas size on SE.
- [ ] Fix `canvasSyncTrigger` unnecessary re-evaluation.
- [ ] Replace `DispatchQueue.main.asyncAfter` with cancellable Tasks in onboarding.
- [ ] Fix Dark Mode hardcoded colors in StepBalanceCard, PaperTicketView.
- [ ] Fix PaperTicketView timer leak.
- [ ] Fix manual pluralization in PaperTicketView.
- [ ] Update all Settings pages to use system nav bar.
- [ ] Add close button to PayGateView.

**Tests**
- [ ] Use dedicated UserDefaults per test in BudgetEngineTests.
- [ ] Add DST timezone tests for DayBoundary.
- [ ] Replace MockHealthKitService with configurable mock.
- [ ] Complete privacy manifest for all Required Reason APIs.

**Performance**
- [ ] Cache decoded FamilyActivitySelections in ShieldRebuildHelper.
- [ ] Pre-decode widget timeline data once per generation.

### Low Priority (P3) — Backlog

- [ ] Remove dead files: `CloudKitService.swift`, `LocationPermissionRequester.swift`.
- [ ] Remove dead code: `BudgetEngine.consume/remainingMinutes`, `loadAppSelection`, `Tariff.entryCostSteps`.
- [ ] Remove dead views: `OptionEntrySheet`, `ColorPaletteView`, `QuickStatusView`.
- [ ] Replace `tintedImageCache` static dict with `NSCache`.
- [ ] Downscale wallpaper in widget timeline provider.
- [ ] Remove `com.apple.developer.applesignin` from DeviceActivityMonitor entitlements.
- [ ] Fix `SignInWithAppleButton` custom clipShape — use default shape.
- [ ] Collect timing constants into `AppConstants.Timing`.
- [ ] Use `timeInterval: 1` for "immediate" notification triggers.
- [ ] Add `kSecAttrSynchronizable: false` to Keychain.
- [ ] Add negative/adversarial tests.
- [ ] Document `EnergyDefaults` rationale.
- [ ] Add `@unchecked Sendable` to `NetworkClient`.

---

## Severity Summary

| Domain | P0 | P1 | P2 | P3 | Total |
|--------|----|----|----|----|-------|
| Architecture & Core Logic | 2 | 11 | 22 | 8 | 43 |
| UI/UX & Accessibility | 0 | 8 | 26 | 16 | 50 |
| Security, Extensions & Tests | 1 | 7 | 17 | 10 | 35 |
| **Total** | **3** | **26** | **65** | **34** | **128** |

---

*Report generated by 3 independent senior iOS engineers reviewing all 135 Swift files across 7 targets.*
