 # Proof (Steps4) — Full Application Audit v3

**Date:** February 16, 2026  
**Scope:** Post-fix re-audit — iOS app, Supabase, Admin Panel, Telegram Bot, extensions

---

## Immediate Fixes Applied During This Audit

| Issue | Status |
|-------|--------|
| Duplicate files (ShieldGroupSettingsView.swift, ShieldRowView.swift) leftover from rename | **FIXED** — deleted |
| Dead TestFile.swift | **FIXED** — deleted |

---

## Critical

### CRIT-01: Race Condition in `check_admin_rate_limit` on Concurrent First-Time IPs

**File:** `supabase/migrations/20260216_login_rate_limiting.sql:27-33`

`SELECT ... FOR UPDATE` returns `NOT FOUND` for a new IP, then `INSERT` runs. Two concurrent requests from the same new IP both see `NOT FOUND` (no row to lock), both INSERT, one gets a primary key violation → 500 error → fail-open (allows login).

**Fix:** Replace with `INSERT ... ON CONFLICT DO UPDATE` for atomic upsert.

---

### CRIT-02: SECURITY DEFINER Functions Without `SET search_path`

**Files:** All `SECURITY DEFINER` functions across migrations:
- `sum_energy_delta`, `count_energy_ledger` (energy RPCs)
- `check_admin_rate_limit`, `cleanup_login_attempts` (rate limiting)

These execute with elevated privileges but don't pin `search_path`. Authenticated users can `SET search_path` to a schema with malicious shadow tables.

**Fix:** Add `SET search_path = public` to every `SECURITY DEFINER` function.

---

## High

### HIGH-01: HealthKitService Data Race

**File:** `Services/HealthKitService.swift:33-34, 219, 306-307`

`lastStepCount`, `isObserving`, `isRequestingAuthorization` are unprotected mutable properties. HK query callbacks execute on arbitrary background queues and write these properties concurrently with `@MainActor` reads.

**Fix:** Convert `HealthKitService` to an `actor`, or dispatch all mutable state writes to `@MainActor`.

---

### HIGH-02: Onboarding Swipe Bypasses Permission Prompts

**File:** `Views/OnboardingStoriesView.swift:90-98`

`TabView` with `.page` style allows free swiping between slides. Permission requests (HealthKit, notifications, FamilyControls) only fire on "Next" button tap. Users can swipe past them entirely.

**Fix:** Add `.scrollDisabled(true)` to force use of the Next button, or trigger permissions via `onChange(of: index)`.

---

### HIGH-03: `objectWillChange` Subscription Triggers Canvas Sync on Every Model Change

**File:** `Views/GalleryView.swift:148`

`.onReceive(model.objectWillChange)` fires on ANY `@Published` property change on AppModel — balance, auth, tickets, everything. Each fires `syncCanvasWithModel()` which reads multiple properties, compares, potentially saves to disk + syncs Supabase.

**Fix:** Replace with targeted `onChange(of:)` on specific canvas-relevant properties.

---

### HIGH-04: GalleryView.dayCanvas Goes Stale Across Midnight

**File:** `Views/GalleryView.swift:33`

`@State private var dayCanvas` initialized with today's `dayKey` at struct creation. If the app stays foregrounded across midnight, the canvas still references yesterday's key. `loadCanvas()` only runs in `onAppear`.

**Fix:** Add `scenePhase` observer or `onChange` that detects day boundary change and reloads.

---

### HIGH-05: Telegram Bot Silently Swallows All Handler Errors

**File:** `tg-admin/src/index.ts:551-559`

The outer catch calls `request.clone().json()` to extract chat ID, but `request.json()` was already consumed. `request.clone()` throws TypeError, inner `catch {}` eats it. All runtime errors → zero feedback to admin.

**Fix:** Save parsed update before dispatching, use it in the error handler.

---

### HIGH-06: User Data Interpolated Into Telegram HTML Without Escaping

**File:** `tg-admin/src/index.ts` — lines 474-475, 496, 648, 660, 732

`u.email`, `u.nickname`, `u.ban_reason`, `/setnick` args, LLM responses interpolated into `parse_mode: "HTML"` messages. Values containing `<`, `>`, `&` break messages or render as HTML.

**Fix:** Add `function esc(s: string) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }` and apply to all user-controlled values.

---

### HIGH-07: Dead "History" Button in Telegram Bot

**File:** `tg-admin/src/index.ts:404` (definition) vs `handleCallbackQuery` (no handler)

`userActionsKeyboard` registers a "History" button with `callback_data: history:${userId}`, but `handleCallbackQuery` has no `history:` branch. Pressing it triggers "Unknown action" toast.

**Fix:** Implement handler or remove button.

---

## Medium

### MED-01: `NSKeyedArchiver` in Computed Properties on Render Path

**Files:** `Components/PaperTicketView.swift:279-284`, `TicketGroupSettingsView.swift:19-68`

`ticketTitle` calls `NSKeyedArchiver.archivedData` + `base64EncodedString` + UserDefaults lookup every body evaluation, for every visible ticket.

**Fix:** Cache resolved title in `@State` via `onAppear`, or maintain static LRU cache.

---

### MED-02: Avatar Image Data Stored in UserDefaults

**File:** `Services/AuthenticationService.swift:262-269`

Potentially hundreds of KB of avatar binary data in `UserDefaults.standard`. Bloats plist, slows all UserDefaults access.

**Fix:** Write to Application Support directory. Store only file path in UserDefaults.

---

### MED-03: Non-Atomic CloudKit Sync

**File:** `Services/CloudKitService.swift:62-92, 123-153, 180-205`

Pattern: delete ALL records → save new ones one-by-one. App kill between delete and save = permanent data loss. Each save = separate network round trip.

**Fix:** Use `CKModifyRecordsOperation` to batch deletes+saves atomically.

---

### MED-04: `fatalError` in Nonce Generation

**File:** `Services/AuthenticationService.swift:944-946`

`SecRandomCopyBytes` failure triggers `fatalError` instead of graceful recovery.

**Fix:** Make `randomNonceString` throwing, catch in caller.

---

### MED-05: `setNotificationCategories` Overwrites All Categories

**File:** `AppModel.swift:676-683`

Each `scheduleReturnNotification()` replaces ALL categories with only `STEPS_REMINDER`, wiping `ACCESS_EXPIRED`.

**Fix:** Register all categories once at startup.

---

### MED-06: BudgetEngine Not `@MainActor`

**File:** `Models/BudgetEngine.swift`

Has `@Published` state but no `@MainActor`. Called from async contexts. Off-main-thread mutations of `@Published` will crash.

**Fix:** Mark `BudgetEngine` as `@MainActor`.

---

### MED-07: PersistenceManager Init Directory Creation Race

**File:** `Services/PersistenceManager.swift:8-19`

`init()` spawns detached `Task` to create directory. Callers can access the directory path before Task completes.

**Fix:** Create directory synchronously in `init()`.

---

### MED-08: CategoryDetailView Decodes UserDefaults Per Row Per Render

**File:** `Views/CategoryDetailView.swift:272-277`

`getEntryColor(for:)` calls `loadEntry(for:)` → UserDefaults read + JSON decode for each option, every body evaluation.

**Fix:** Cache in `@State` dictionary, populate in `onAppear`.

---

### MED-09: `contentShape(Circle().size(...))` Not Centered

**File:** `Views/GalleryView.swift:248, 275`

Circle hit target at origin (0,0), not centered on button frame. Tap target offset.

**Fix:** Use `.contentShape(Circle())` on a container with explicit `.frame()`.

---

### MED-10: Server Actions on User Detail Page Have No Error Handling

**File:** `admin-panel/src/app/(admin)/users/[id]/page.tsx:35-56`

`handleBan`, `handleUnban`, `handleGrantEnergy` don't catch errors. Supabase failure → generic 500 page.

**Fix:** Wrap in try/catch, redirect with error param.

---

### MED-11: `handleGrantEnergy` Has No Magnitude Cap

**File:** `admin-panel/src/app/(admin)/users/[id]/page.tsx:49-56`

No upper bound on energy grant amount. Admin could accidentally grant 999999999.

**Fix:** Add `const MAX_GRANT = 100_000; if (Math.abs(delta) > MAX_GRANT) return;`

---

### MED-12: Middleware Health-Check Exclusion Regex Over-Broad

**File:** `admin-panel/src/middleware.ts:21-23`

`/((?!api/health).*)` excludes any path starting with `/api/health*`, not just `/api/health` exactly.

**Fix:** Use `/((?!api/health$).*)` for exact match.

---

### MED-13: No Automatic Cleanup for `admin_login_attempts`

**File:** `supabase/migrations/20260216_login_rate_limiting.sql:53-65`

`cleanup_login_attempts()` exists but no cron job. Table grows indefinitely.

**Fix:** Add `pg_cron` hourly schedule.

---

### MED-14: Nickname TOCTOU Race

**File:** `tg-admin/src/index.ts:303-326, 627-649`

Check `isNicknameUnique` via SELECT, then SET via PATCH. No UNIQUE constraint on `users.nickname` — duplicates can slip through.

**Fix:** Add `UNIQUE` constraint on `users.nickname`.

---

### MED-15: DayEndSettingsView Silently Resets to 21:00

**File:** `Views/DayEndSettingsView.swift:92-99`

If stored day-end time isn't in `allowedMinutes`, it hard-resets to 21:00 with no user notification.

**Fix:** Snap to nearest allowed value instead.

---

### MED-16: `TicketGroupSettingsView` `@State var group` Creates Disconnected Copy

**File:** `Views/TicketGroupSettingsView.swift:8`

`@State var group: TicketGroup` is a local copy. Parent changes don't propagate in. Uses `model.updateTicketGroup(group)` on save which works, but it's fragile.

**Fix:** Document the intent or switch to `@Binding`.

---

## Low

### LOW-01: Unreachable Dead Code in `deleteOption`

**File:** `AppModel+DailyEnergy.swift:270-289`

Lines after early returns for built-in and custom options are unreachable.

### LOW-02: `FamilyControlsService.buildMinuteEvents` Ignores `minuteTariffEnabled`

**File:** `Services/FamilyControlsService.swift:104-106`

Creates events for ALL apps regardless of the flag. Bug when minute mode is re-enabled.

### LOW-03: `CanvasStorageService` Recreates Directories on Every Property Access

**File:** `Services/CanvasStorageService.swift:16-36`

Computed properties call `fileExists` + `createDirectory` on every access.

### LOW-04: Force Unwrap `until!` in Ban Check

**File:** `Services/AuthenticationService.swift:507`

### LOW-05: Orphaned `CFNotificationCenterRemoveObserver` in `deinit`

**File:** `AppModel.swift:851-858`

No corresponding `AddObserver` call found.

### LOW-06: `ProfileLocationManager` Completion Closure Never Nilled

**File:** `Services/ProfileLocationManager.swift:12, 74-76`

Potential retain cycle.

### LOW-07: Deprecated `UserDefaults.synchronize()` Call

**File:** `Intents/ExportCanvasWallpaperIntent.swift:106`

### LOW-08: `PayGateBackgroundStyle.displayNameRU` Returns English

**File:** `Models/PayGateBackgroundStyle.swift:24-33`

### LOW-09: Dead Code: `MeView.optionIcon` and `assetImageName`

**File:** `Views/MeView.swift:456-462`

### LOW-10: Dead Code: `MainTabView.Tab.shortTitle` Identical to `title`

**File:** `Views/MainTabView.swift:52-60`

### LOW-11: `RadialHoldMenu` Creates Haptic Generators as Struct Properties

**File:** `Views/RadialHoldMenu.swift:24-25`

### LOW-12: `NotificationDelegate.model` Could Be Nil on Cold Launch From Notification

**File:** `Services/NotificationDelegate.swift:27`

### LOW-13: `StepBalanceCard.timeUntilReset` Goes Stale

**File:** `Components/StepBalanceCard.swift:52-63`

### LOW-14: `usersListKeyboard` Uses `any[]` Parameter

**File:** `tg-admin/src/index.ts:426`

### LOW-15: `TELEGRAM_WEBHOOK_SECRET` Declared Optional in Type But Required at Runtime

**File:** `tg-admin/src/index.ts:9`

### LOW-16: Missing RLS DELETE Policies on 4 Tables

**Files:** `user_day_canvases`, `user_analytics_events`, `user_preferences`, `user_day_snapshots`

---

## Cosmetic

- `catch (e: any)` in dashboard and users pages → use `unknown`
- Root layout metadata still has create-next-app boilerplate
- Deprecated `UIGraphicsBeginImageContextWithOptions` in `GenerativeCanvasView.swift:134`

---

## Priority Matrix

### P0 — Fix Immediately

| # | Issue | Effort |
|---|-------|--------|
| 1 | CRIT-01: SQL race condition in rate limiter | 15 min |
| 2 | CRIT-02: search_path hijack in SECURITY DEFINER functions | 15 min |
| 3 | HIGH-01: HealthKitService data race | 30 min |
| 4 | HIGH-05: Telegram bot swallows all errors | 15 min |
| 5 | HIGH-06: HTML injection in Telegram messages | 15 min |

### P1 — Fix This Sprint

| # | Issue | Effort |
|---|-------|--------|
| 6 | HIGH-02: Onboarding swipe bypasses permissions | 10 min |
| 7 | HIGH-03: objectWillChange canvas over-sync | 30 min |
| 8 | HIGH-04: GalleryView stale across midnight | 15 min |
| 9 | HIGH-07: Dead History button | 10 min |
| 10 | MED-01: NSKeyedArchiver on render path | 30 min |
| 11 | MED-04: fatalError in nonce generation | 10 min |
| 12 | MED-05: Notification categories overwrite | 15 min |
| 13 | MED-06: BudgetEngine not @MainActor | 5 min |
| 14 | MED-10: Server actions error handling | 15 min |
| 15 | MED-11: Grant energy magnitude cap | 5 min |
| 16 | MED-14: Nickname TOCTOU race | 10 min |

### P2 — Backlog

| # | Issue | Effort |
|---|-------|--------|
| 17 | MED-02: Avatar in UserDefaults | 30 min |
| 18 | MED-03: Non-atomic CloudKit sync | 1 hour |
| 19 | MED-07: PersistenceManager race | 10 min |
| 20 | MED-08: CategoryDetailView per-row decode | 15 min |
| 21 | MED-12: Middleware regex | 5 min |
| 22 | MED-13: Login attempts cleanup cron | 10 min |
| 23 | All LOW items (16 items) | 2 hours |
| 24 | All Cosmetic items (3 items) | 15 min |

---

## Score Card

| Category | v2 Audit | v3 Audit |
|----------|----------|----------|
| Critical | 0 | 2 (new: SQL race, search_path) |
| High | 2 | 7 (new: data race, onboarding, canvas, tg-bot) |
| Medium | 4 | 16 |
| Low | varies | 16 |
| Cosmetic | — | 3 |

**Note:** v2 audit items are all resolved. v3 issues are NEW findings from deeper analysis of concurrency, render-path performance, backend security, and edge cases.

---

*End of v3 audit. Files scanned: 95 Swift, 17 TypeScript/TSX, 4 SQL migrations, 3 extension directories.*
