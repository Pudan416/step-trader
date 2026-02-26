# Proof (Steps4) — Full Application Audit v4

**Date:** February 16, 2026  
**Scope:** Post-fix re-audit — iOS app, Supabase, Admin Panel, Telegram Bot, extensions  
**Prior audits:** v1, v2, v3 — all items resolved. This audit finds **new** issues only.

---

## Critical

### CRIT-01: SQL Migration Ordering Breaks Fresh Deployments

**File:** `supabase/migrations/20260216_add_energy_aggregation_rpcs.sql` vs `20260216_create_missing_tables.sql`

Supabase CLI runs migrations alphabetically. `_add_energy_aggregation_rpcs` sorts before `_create_missing_tables`. Both `sum_energy_delta` and `count_energy_ledger` use `LANGUAGE sql` (validated at CREATE time). The `energy_ledger` table doesn't exist yet → hard failure on fresh deploy.

**Fix:** Rename to `20260216b_add_energy_aggregation_rpcs.sql` so it sorts after table creation.

---

## High

### HIGH-01: RPC Functions Callable by `anon` Role (Data Leakage)

**File:** `supabase/migrations/20260216_add_energy_aggregation_rpcs.sql:37-39`

PostgreSQL grants `EXECUTE` to `PUBLIC` by default. The migration adds `GRANT` to `authenticated`/`service_role` but never revokes `PUBLIC`. Any unauthenticated client can call `sum_energy_delta()` and `count_energy_ledger()`.

**Fix:** Add `REVOKE ALL ON FUNCTION ... FROM public, anon;` before the GRANTs.

---

### HIGH-02: ShieldActionExtension Ignores `liteTicketConfig_v1`

**File:** `ShieldAction/ShieldActionExtension.swift:71-76`

Only checks `ticketGroups_v1` and `shieldGroups_v1`. The main app writes a compact `liteTicketConfig_v1` format that DeviceActivityMonitor reads. ShieldAction can't find groups in lite format → unlocked apps incorrectly show the shield.

**Fix:** Port `loadTicketGroupsForExtension` (with `LiteShieldConfigDecoded`) from DeviceActivityMonitor into ShieldAction.

---

### HIGH-03: Auth Tokens Stored in UserDefaults, Not Keychain

**File:** `Services/AuthenticationService.swift:350-353`

Supabase `accessToken` and `refreshToken` are stored as plain JSON in `UserDefaults.standard`. Not encrypted, included in backups, readable by any process with entitlements.

**Fix:** Use iOS Keychain (`SecItemAdd`/`SecItemCopyMatching`) with `kSecAttrAccessibleAfterFirstUnlock`.

---

### HIGH-04: `bundleId` Passed Where `groupId` Expected (PayGate Never Opens)

**File:** `StepsTraderApp.swift:243-246`

In the `com.steps.trader.local.paygate` notification handler, `model.startPayGateSession(for: bundleId)` is called. But `startPayGateSession(for:)` expects a **groupId** — it does `ticketGroups.first(where: { $0.id == groupId })`. Always fails the lookup.

**Fix:** Change to `model.openPayGateForBundleId(bundleId)`.

---

### HIGH-05: `fatalError` in MetalSmudgeRenderer Private Init

**File:** `Metal/MetalSmudgeRenderer.swift:143`

`private override init() { fatalError("Use MetalSmudgeRenderer.create()") }` — NSObject subclasses can have `init()` invoked via KVO or other dynamic dispatch.

**Fix:** Replace with `@available(*, unavailable)` annotation.

---

## Medium

### MED-01: `NoteReadTracker` Missing `@MainActor`

**File:** `Models/Note.swift:13-40`

`ObservableObject` with `@Published` properties but no `@MainActor`. `markRead()` from background context → runtime warning.

---

### MED-02: `ProfileLocationManager` Mutates `@Published` Off Main Thread

**File:** `Services/ProfileLocationManager.swift:42-49`

`locationManagerDidChangeAuthorization` sets `isLoading` and `errorMessage` directly without `DispatchQueue.main.async`.

---

### MED-03: `CanvasStorageService` Directory Checks on Every Property Access

**File:** `Services/CanvasStorageService.swift:16-36`

Computed properties call `fileManager.fileExists` + `createDirectory` per access. Convert to `lazy var`.

---

### MED-04: Avatar Binary Data in UserDefaults

**File:** `Services/AuthenticationService.swift:308-315`

Potentially hundreds of KB. Bloats plist, slows all UserDefaults access. Write to Application Support instead.

---

### MED-05: `clearExpiredDayPasses` Pre-Computed Day-Start Off-by-One

**File:** `AppModel+Payment.swift:222-228`

Passes `currentDayStart(for: Date())` to `isSameCustomDay()`, which internally calls `currentDayStart()` again. At exact boundary time, double-mapping can produce wrong day.

**Fix:** Pass raw `Date()` instead.

---

### MED-06: `UserEconomyStore` Persistence Race — Reference Capture in Fire-and-Forget Tasks

**File:** `Stores/UserEconomyStore.swift:131-141`

`appStepsSpentByDay` captured by reference in `Task`. By the time Task executes, dict may have been mutated. Also `try?` swallows errors silently.

**Fix:** Capture snapshot: `let snapshot = appStepsSpentByDay` before `Task`.

---

### MED-07: `savePastDaySnapshot` Double-Decodes From Disk

**File:** `AppModel+DailyEnergy.swift:451-459`

Calls `loadPastDaySnapshots()` which reads+decodes file, then writes again. On 90 days of history, this is multiple MB of redundant JSON work.

---

### MED-08: `withTimeout` Uses `rethrows` But Contains Independent Throw

**File:** `AppModel.swift:726-737`

`Task.sleep` throws `CancellationError` independently of the `operation` closure. Should be `throws`, not `rethrows`.

---

### MED-09: Open Redirect via Protocol-Relative URLs in Admin Login

**File:** `admin-panel/src/app/login/page.tsx:13`

`next` param validated with `startsWith("/")` — accepts `//evil.com`. Browsers interpret as `https://evil.com`.

**Fix:** Add `&& !raw.startsWith("//")`.

---

### MED-10: tg-admin `/grant` Command Has No Amount Cap

**File:** `tg-admin/src/index.ts:616-621, 801-804`

Admin-panel enforces `MAX_GRANT = 100_000`. The tg-admin bot has no cap — `/grant <id> 99999999` works.

**Fix:** Add matching `MAX_GRANT` check.

---

### MED-11: tg-admin Callback `grant:` No NaN Guard

**File:** `tg-admin/src/index.ts:801-804`

Malformed callback data `grant:userId:` → `Number(undefined)` = NaN → passed to Supabase → violates NOT NULL.

**Fix:** Validate `Number.isFinite(amount) && amount !== 0` before granting.

---

### MED-12: DeviceActivityMonitor `dictionaryRepresentation()` Loads All Keys

**File:** `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift:206-244`

Called on every monitor callback. Copies entire UserDefaults into memory in a ~6MB-limited extension.

**Fix:** Use known group IDs to check specific keys instead.

---

### MED-13: `StepBalanceCard` Reset Timer Never Updates

**File:** `Views/Components/StepBalanceCard.swift:52-63`

`timeUntilReset` reads `Date()` but nothing triggers re-evaluation. Stale countdown.

**Fix:** Wrap in `TimelineView(.periodic(from: .now, by: 60))`.

---

### MED-14: `StatusRow.ConnectionStatus.color` Always Returns `.primary`

**File:** `Views/Components/StatusRow.swift:13`

All three statuses (connected/disconnected/warning) return same color, defeating visual distinction.

---

### MED-15: `CategoryDetailView.getEntryColor` Mutates @State During Body

**File:** `Views/CategoryDetailView.swift:276-286`

`DispatchQueue.main.async { entryColorCache[optionId] = color }` during body evaluation → guaranteed double-render.

**Fix:** Remove the async mutation; just return the computed color on cache miss.

---

### MED-16: `ProfileEditorView.countries` Rebuilds 250+ Items Per Body Eval

**File:** `Views/ProfileEditorView.swift:19-26`

Computed property iterates all ISO regions, localizes, sorts. Never changes at runtime.

**Fix:** Convert to `private static let`.

---

### MED-17: `GenerativeCanvasView.isDarkBackground` Allocates UIColor Every Frame

**File:** `Views/GenerativeCanvasView.swift:32-37`

Called per element per frame (~20fps × N). Creates UIColor + HSBA extraction each time.

**Fix:** Compute once per render pass.

---

### MED-18: `MeView.loadTransactionNameMap()` Synchronous Disk I/O on Main Thread

**File:** `Views/MeView.swift:378-390`

`Data(contentsOf:)` + `JSONDecoder` on main thread during `onAppear`.

---

### MED-19: `AppleSignInDelegate` Missing `@MainActor`

**File:** `Views/OnboardingStoriesView.swift:1049-1062`

Accesses `UIApplication.shared.connectedScenes` and UIWindow off main actor.

---

## Low

### LOW-01: `Color.toHex()` Mishandles Grayscale Colors
**File:** `Models/CanvasElement.swift:330-338` — 2-component CGColors (`.white`, `.gray`, `.black`) always return `#FFFFFF`.

### LOW-02: Dead Code: `isInstagramSelected` Property
**File:** `AppModel.swift:252-273` — No view binds to it, no code sets it to true.

### LOW-03: Dead Code: `MeView.optionIcon(for:)` and `assetImageName(for:)`
**File:** `Views/MeView.swift:456-462` — Private, zero callers.

### LOW-04: Dead Code: `MainTabView.Tab.shortTitle` Identical to `title`
**File:** `Views/MainTabView.swift:52-60` — Returns same values; remove and use `title`.

### LOW-05: Dead Code: `PayGateView.sendAppToBackground()` Is No-Op
**File:** `Views/PayGateView.swift:273-276` — Button label says "close app" but method does nothing.

### LOW-06: `IntroImagesView` Hardcodes `7` Instead of `imageNames.count - 1`
**File:** `Views/IntroImagesView.swift:50,56`

### LOW-07: Deprecated `NavigationView` Used in 7 Files
**Files:** CategorySettingsView, TicketGroupSettingsView, AutomationGuideView, ProfileEditorView, CountryPickerView, AppSelectionComponents, TimeAccessPickerSheet. Replace with `NavigationStack`.

### LOW-08: `RadialHoldMenu` Haptic Generators Recreated Per Struct Init
**File:** `Views/RadialHoldMenu.swift:24-25` — Make `static let`.

### LOW-09: `PaperTicketView.titleCache` Static Var Unprotected From Data Races
**File:** `Views/Components/PaperTicketView.swift:23`

### LOW-10: `BlockingStore.tokenKeyCache` Grows Unbounded
**File:** `Stores/BlockingStore.swift:14-22` — Never evicted. Clear on shield rebuild.

### LOW-11: Duplicate Expiry Notifications for Same Group
**File:** `AppModel+PayGate.swift:89-93` — Second payment doesn't cancel first notification.

### LOW-12: `ExportCanvasWallpaperIntent` Calls Deprecated `synchronize()`
**File:** `Intents/ExportCanvasWallpaperIntent.swift:178`

### LOW-13: Missing `dusk` Palette in Shortcuts `ColorPaletteOption`
**File:** `Intents/ExportCanvasWallpaperIntent.swift:56-82`

### LOW-14: `Tariff.free` and `Tariff.easy` Have Identical `stepsPerMinute`
**File:** `Models/Types.swift:107-114`

### LOW-15: `NotificationManager` Missing `Sendable` Conformance
**File:** `NotificationManager.swift:5`

### LOW-16: `NoteCatalog.random(excluding:)` Fragile Reject-Sampling Loop
**File:** `Models/Note.swift:82-87`

### LOW-17: DeviceActivityMonitor `print()` Instead of `MonitorLogger`
**File:** `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift:219,232,241`

### LOW-18: `information_schema` Column Checks Missing `table_schema` Filter
**Files:** `supabase/migrations/20260130_add_wallpaper_shortcut_tracking.sql:7-8`, `20260216_user_preferences_and_snapshots.sql` (8 occurrences)

### LOW-19: `handleGrantEnergy` Silently Swallows Invalid Input
**File:** `admin-panel/src/app/(admin)/users/[id]/page.tsx:58-62` — Returns with no redirect/error.

### LOW-20: tg-admin Error Handler Leaks Raw Internal Error Details
**File:** `tg-admin/src/index.ts:557-563` — Could expose Supabase URLs, schema hints.

### LOW-21: `OnboardingStoriesView.feedSelectionSlide` Allocates Array Per Body Eval
**File:** `Views/OnboardingStoriesView.swift:843-852` — `popularApps` array. Make `static let`.

### LOW-22: `BudgetEngine` Redundant UserDefaults Fallback
**File:** `Models/BudgetEngine.swift:44-47` — `g.object(forKey:) as? Int ?? g.integer(forKey:)` reads same key twice.

### LOW-23: `loadTicketGroupsForExtension` Decoded Twice in `setupBlockForMinuteMode`
**File:** `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift:346,411`

---

## Priority Matrix

### P0 — Fix Before Deploy

| # | Issue | Effort |
|---|-------|--------|
| 1 | CRIT-01: Migration ordering | 2 min (rename file) |
| 2 | HIGH-01: REVOKE anon from RPCs | 5 min |
| 3 | HIGH-04: bundleId→groupId PayGate bug | 2 min |
| 4 | MED-09: Open redirect in admin login | 2 min |
| 5 | MED-10: tg-admin /grant cap | 5 min |
| 6 | MED-11: tg-admin callback grant NaN | 5 min |

### P1 — Fix This Sprint

| # | Issue | Effort |
|---|-------|--------|
| 7 | HIGH-02: ShieldAction lite config | 30 min |
| 8 | HIGH-03: Auth tokens to Keychain | 45 min |
| 9 | HIGH-05: MetalSmudgeRenderer fatalError | 2 min |
| 10 | MED-01–MED-08: Concurrency + perf fixes | 2 hours |
| 11 | MED-12–MED-19: View fixes | 1.5 hours |

### P2 — Backlog

| # | Issue | Effort |
|---|-------|--------|
| 12 | All LOW items (23) | 3 hours |

---

## Score Card

| Category | v3 | v4 |
|----------|-----|-----|
| Critical | 2 (fixed) | 1 (migration ordering) |
| High | 7 (fixed) | 5 (new: anon RPCs, shield ext, keychain, paygate bug, metal fatalError) |
| Medium | 16 (fixed) | 19 |
| Low | 16 (fixed) | 23 |

**Total new findings: 48** across iOS app (24), Views (18), Backend + Extensions (12). Note: some overlap between iOS core and Views audits was deduplicated.

---

*End of v4 audit. Files scanned: 98 Swift, 17 TypeScript/TSX, 6 SQL migrations, 3 iOS extension directories.*
