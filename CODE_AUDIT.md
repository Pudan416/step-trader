# Nowhere (StepsTrader) Code Audit

Regenerated **2026-06-01** (fresh whole-project pass via `ios-code-audit`). Scope: ~52,800 LOC across 225 Swift files + 3 Metal kernels across 7 targets (Steps4, DeviceActivityMonitor, ShieldConfiguration, ShieldAction, UnlockWidgetExtension, Steps4Tests, Steps4UITests) plus the local `OnboardingPreview` SPM package. `admin-panel/`, `tg-admin/`, `web/`, `build/`, `output/`, `tmp/`, `docs/`, and `Scripts/` are excluded.

`OnboardingPreview/Sources/OnboardingStoriesView.swift` is a **symlink** to `StepsTrader/Views/OnboardingStoriesView.swift` — audited once, not double-counted.

**Section numbers are stable across audit runs by design** so external references ("fix §5.2", "is §9.2 done?") keep resolving to the same finding. This snapshot carries forward the numbering established in the 2026-05-26 audit (preserved in git at commit `a6f0a92`). Findings resolved in prior sessions are kept as one-line ✅ markers so their numbers don't shift; **open** and **newly-discovered** findings are written in full.

A clean Debug build of the `Steps4` scheme (iOS Simulator) produced **one warning** — a CFBundleShortVersionString mismatch between an app extension (`1.1.2`) and the parent app (`1.2`), see §2. No code warnings. The project still compiles in Swift 5 mode without strict concurrency, so §3 items remain **latent** (they fire on the Swift 6 migration).

**There are no Critical findings.** Three agent-flagged "Critical" items were demoted during verification (see §12).

---

## 1. Executive summary

Highest-impact items, in priority order (✅ = resolved in a prior session):

1. ✅ **[Medium] Avatar migration deletes the UserDefaults copy even when the disk write fails** — §5.11. Resolved 2026-06-11.
2. **[High] App-Group `UserDefaults` compound read-modify-write is unsynchronized across processes** — §5.2 — `BlockingStore.swift`, `DeviceActivityMonitorExtension.swift`, **+ new site** `AppModel+PayGate.swift:85-96`. **← OPEN.**
3. ✅ **[Medium] Duplicate source-of-truth for the `payGateDismissedUntil_v1` key** — §5.12. Resolved 2026-06-11.
4. **[High] Oversized SwiftUI views / files (1951 / 1398 / 1145 / 908 / 885 LOC) couple state, network, and rendering** — §9.2 — `OnboardingStoriesView`, `GalleryView`, `AppModel+DailyEnergy`, `MeView`, `CategoryDetailView`. **← OPEN.**
5. **[Medium] `ObservableObject` + `@Published` still used where `@Observable` fits (iOS 17.5+ supports it)** — §4.3 — `AppModel` + every store/service. **← OPEN.**
6. **[Medium] Hot SwiftUI views compute layout/sort/format in `body` without memoization** — §7.3 — `GalleryView`, `MeView`, `CategoryDetailView`. **← OPEN.**
7. ✅ **[Low] Build-config: extension version string `1.1.2` ≠ app `1.2`** — §2. Resolved (all 14 `MARKETING_VERSION` entries = 1.2 as of 2026-06-11; build is warning-free).
8. ✅ **[High] No Debug/Release Supabase URL split** — §6.1. Resolved 2026-05-29.
9. ✅ **[High] PayGate monitoring-failure refund had no UI feedback** — §5.1. Resolved 2026-05-26.
10. ✅ **[High] `loadStoredSession` ignored the UserDefaults shadow on early-boot Keychain lock** — §5.6. Resolved 2026-05-28.

---

## 2. Quick wins (≤30 min each)

- ✅ **Build-config version mismatch.** Resolved — all targets at `MARKETING_VERSION = 1.2`, clean build produces no warning (verified 2026-06-11).
- **Asset-name typo `onboarding_figuer_1` (NEW).** See §9.14 — rename the asset + 3 string references.
- ✅ **Duplicate key constant.** See §5.12 — resolved 2026-06-11.
- **Centralize JPEG compression constants (NEW).** See §9.13 — three different magic qualities (0.75 / 0.8 / 0.85).
- **`print()` in `OnboardingPreview/Sources/Stubs.swift:100` not `#if DEBUG`-gated.** See §9.15 — preview-only package, low impact.

Prior quick-wins (SharedKeys consolidation, `[weak self]`/cancellation on sinks, DEBUG-gating onboarding prints) remain resolved.

---

## 3. Concurrency

Still Swift 5 mode, strict concurrency off — everything here is **latent** until the Swift 6 / `SWIFT_STRICT_CONCURRENCY=complete` migration. §3.1–§3.10 were resolved in prior sessions (verified still in place this pass: `lastStepCount` is NSLock-guarded at `HealthKitService.swift:43-48`; `initialFetchTask` tracked + cancellation-gated at `HealthKitService.swift:385-413`; HK observer re-fetch gates on `isObserving`; Combine sink Tasks tracked).

### 3.1 ✅ _RESOLVED — sign-in Task tracked + cancellation-aware._
### 3.2 ✅ _RESOLVED — `UnsafeSendableBox` deleted, HK auth uses async overload._
### 3.3 ✅ _RESOLVED — `UNUserNotificationCenter.add()` on async overload._
### 3.4 ⏸ _DEFERRED — needs `SWIFT_STRICT_CONCURRENCY=complete` to surface caller sites._
### 3.5 ✅ _RESOLVED — Combine sink Tasks tracked + cancellable._
### 3.6 ✅ _RESOLVED — HK observer re-fetch gates on `isObserving`._
### 3.7 ✅ _RESOLVED — diagnostic HK source breakdown wrapped in `#if DEBUG`._
### 3.8 ✅ _RESOLVED — threading contract documented on `ShieldRebuildHelper`._
### 3.9 ✅ _RESOLVED — initial-fetch Task tracked via `initialFetchTask`._
### 3.10 ✅ _RESOLVED — `BlockingStore` Task.sleep guarded by `Task.isCancelled`._

### 3.11 `UIWindowScene.windows` accessed directly
- **Location:** `StepsTrader/Views/Onboarding/AppleSignInCoordinator.swift:21-26`, `StepsTrader/Stores/SubscriptionStore.swift` (presentation-anchor lookup)
- **What:** Code reaches for `scene.windows.first` / `flatMap(\.windows)` to find a presentation anchor.
- **Why:** On iPad with two windows / Split View this can resolve the wrong scene (e.g. an Apple Sign-In sheet appearing in the inactive window).
- **Action:** Centralize a single `connectedScenes`-based active-window helper and route both call sites through it.
- **Severity:** Low
- **На практике:** Сегодня работает; ломается только при поддержке iPad Split View с двумя окнами.

### 3.12 Recursive `Timer.scheduledTimer` reschedule can silently stop
- **Location:** `StepsTrader/AppModel.swift:367-378`
- **What:** The day-boundary timer fires `Task { @MainActor [weak self] in self?.checkDayBoundary(); self?.scheduleDayBoundaryTimer() }`; if `self` is nil between fires the recursive reschedule chain ends with no log.
- **Why:** Unreachable in production (`AppModel` lives for the app's lifetime) but breaks in unit tests that recreate the model.
- **Action:** Replace with an `AsyncStream` + `Task.sleep(until:)` scoped to model lifetime, cancelled in `deinit`.
- **Severity:** Low

### 3.13 Long-lived listener / debounce Tasks reassigned without confirming prior teardown (latent)
- **Location:** `StepsTrader/Stores/SubscriptionStore.swift` (`customerInfoStreamTask`, `refreshTask`), `StepsTrader/Services/SupabaseSyncService.swift:24-33` (per-entity sync Tasks), `StepsTrader/Stores/BlockingStore.swift` (debounced save/rebuild Tasks)
- **What:** Each new request does `task?.cancel(); task = Task { … }` — cancellation is requested but not awaited, so the prior Task can still be mid-flight when the new one starts.
- **Why:** Under rapid re-entry a prior sync upload can overlap a new one (duplicate work, not loss). All are tracked + cancelled in `deinit`, so this is a fairness/duplication concern, not a leak.
- **Action:** Where overlap matters (sync uploads), gate with an in-flight flag or serialize via a single actor/`TaskGroup`; otherwise document the cancel-don't-await contract.
- **Severity:** Low (latent)

---

## 4. API modernity

### 4.1 ✅ _RESOLVED — all 16 files migrated to `.sensoryFeedback`._
### 4.2 ✅ _RESOLVED — vestigial `await` removed; 0 code warnings._

### 4.3 `@Published` + `ObservableObject` used where `@Observable` would do
- **Location:** `StepsTrader/AppModel.swift:18-20`, every file in `StepsTrader/Stores/*.swift`, `AuthenticationService.swift`, plus `HealthStore`, `UserEconomyStore`, `BudgetEngine`, `AnnouncementService`, `FamilyControlsService`
- **What:** Stores/services use `@MainActor final class … : ObservableObject` with `@Published`. Deployment target is iOS 17.5, so `@Observable` is available (already used in `Models/Note.swift`).
- **Why:** `@Observable` gives per-property invalidation, drops the Combine dependency, and is a prerequisite for `@Bindable`. Today any step/sleep change re-renders every view observing `AppModel`.
- **Action:** Migrate incrementally; `AppModel` and the stores are the biggest payoff. Linked to §7.3/§7.4.
- **Severity:** Medium
- **На практике:** При любом изменении step count перерисовывается всё дерево вьюх, смотрящих на `AppModel`. `@Observable` перерисует только реально зависящие.

### 4.4 ✅ _RESOLVED — see §3.2._
### 4.5 ✅ _RESOLVED — see §3.3._

### 4.6 No stale `@available` guards below the deployment target
- **Location:** N/A — clean.
- **Severity:** Low (informational).

---

## 5. Bugs / logic errors

### 5.1 ✅ _RESOLVED — PayGate monitoring failure surfaces an alert + dismisses (`AppModel+PayGate.swift:104-119`)._

### 5.2 App-Group `UserDefaults` compound mutations are unsynchronized across processes
- **Location:** `StepsTrader/Stores/BlockingStore.swift` (group save path), `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift` (budget/blocking state), **+ NEW site** `StepsTrader/AppModel+PayGate.swift:85-96` (usage-budget read-modify-write)
- **What:** Individual `set`/`get` is atomic, but read-modify-write sequences (read `usageBudgetKey` → `existing + minutes` → write back; or load JSON → decode → mutate → re-encode → set) have no cross-process coordination. The PayGate site reads `defaults.integer(forKey: budgetKey)`, adds `minutes`, and writes the sum — if the DeviceActivity extension decrements the same budget between the read and write, that decrement is lost.
- **Why:** When the extension fires (time budget exhausted) concurrently with the app mutating the same state, one process can resurrect/overwrite the other's value. State sticks until manually changed.
- **Action:** Move compound App-Group state behind a single `Shared/AppGroupStateStore` with `NSFileCoordinator`-coordinated reads/writes (sync API so the extension can call it). Note: a bare `actor` doesn't compose here — the extension needs synchronous access and `NSFileCoordinator` coordinates files, not `UserDefaults`; design decision required first.
- **Severity:** High
- **Status:** OPEN — deferred to a dedicated session. **Reproduced** 2026-05-29 via `Steps4Tests/AppGroupRMWConcurrencyTests`: two lock-step writers lost exactly 50% of updates vs the serialized control. The race assertion is parked behind `XCTSkipIf(true, …)`; removing that line re-arms it as the regression guard. (The 50% figure is an amplified test, not a production loss rate — the proven point is that *when* a collision occurs an update is silently lost.)
- **На практике:** Если extension стреляет одновременно с пользователем в настройках блокировки / покупкой времени — свежая правка может быть затёрта старой. Узкое окно, но залипает.

### 5.3 ✅ _RESOLVED — HK initial fetch can't write past `stopObservingSteps()`._
### 5.4 ⬇️ _DEMOTED to Low/latent — `@MainActor` + synchronous recompute prevents the described tearing. Becomes real only if a recompute path is made `async` with an `await` between two boundary reads._
### 5.5 ✅ _RESOLVED — Moment IDs stripped at every Supabase sync boundary._
### 5.6 ✅ _RESOLVED — `loadStoredSession` falls back to the UserDefaults shadow (`AuthenticationService.swift:533-548` Keychain-first, UD fallback)._
### 5.7 ✅ _RESOLVED — widget `bundleId` validated against reverse-DNS regex._
### 5.8 ✅ _RESOLVED — re-entrancy guard via `_openingBundleIds` Set._
### 5.9 ✅ _RESOLVED — sleep-merge reads `merged.last` first._

### 5.10 Recursive day-boundary timer reschedule stops on `self == nil`
- See §3.12 (same site, `AppModel.swift:367-378`). **Severity:** Low.

### 5.11 ✅ _RESOLVED 2026-06-11 — `removeObject` moved inside the successful-write path; failed migration keeps the UserDefaults copy for retry._

### 5.12 ✅ _RESOLVED 2026-06-11 — `_payGateDismissedUntilKey` deleted; both call sites use `SharedKeys.payGateDismissedUntil`._

### 5.13 Offline retry queue doesn't prune expired entries before size-truncation
- **Location:** `StepsTrader/Services/SupabaseSyncService.swift:164-180`
- **What:** `enqueueForRetry` appends then truncates to `suffix(maxRetryQueueSize)` without first filtering `isExpired` (3-day TTL). Expired entries are only dropped later in `drainRetryQueue()`.
- **Why:** A long offline period keeps stale-but-not-yet-drained entries occupying queue slots; eviction is purely by recency, so an expired entry can survive while a slightly older fresh one is dropped. Minor — the newest request is always retained (it's appended last).
- **Action:** `queue = queue.filter { !$0.isExpired }` before the size check in `enqueueForRetry`.
- **Severity:** Low

---

## 6. Security

### 6.1 ✅ _RESOLVED 2026-05-29 — per-config `Secrets-Debug/Release.xcconfig` layers + Release host assertion in `NetworkClient.swift` (`SupabaseConfig` rejects non-HTTPS / non-`*.supabase.co` in `#if !DEBUG`)._
### 6.2 No hardcoded secrets in client code
- **Location:** repo-wide grep. All `Bearer …` use validated session tokens; Supabase anon key + RevenueCat key are public client keys.
- **Severity:** Low (informational — clean).
### 6.3 `supabase/functions/send-push/index.ts` is well-hardened
- Env-var validation, constant-time bearer compare, CORS closed, narrow APNs cleanup. **Severity:** Low (use as template).
### 6.4 Handoff token is locally generated and locally verified — by design (`HandoffToken.swift`). **Severity:** Low.
### 6.5 Retry queue stores raw request bodies without integrity check (`SupabaseSyncService.swift`). Optional CRC/HMAC. **Severity:** Low.
### 6.6 Log redaction — truncated user IDs, no raw tokens in `AuthenticationService` logs. **Severity:** Low (clean).
### 6.7 Entitlements XML not opened this run — verify App Group present on every target. **Severity:** Low (out of scope).

---

## 7. Performance

### 7.1 ✅ _RESOLVED — diagnostic HK query DEBUG-gated._
### 7.2 ✅ _RESOLVED (partial) — widget JSONDecoder/Calendar hoisted to module scope; remaining items need Instruments._

### 7.3 Hot SwiftUI views recompute heavy state in `body`
- **Location:** `StepsTrader/Views/GalleryView.swift`, `MeView.swift`, `CategoryDetailView.swift`
- **What:** Large `body` functions compute layout, sort, format, and render in one pass without memoization or `Equatable` leaf views.
- **Why:** Likely cause of scroll/animation lag on older devices (iPhone 11/SE) and full history days.
- **Action:** Profile with SwiftUI Instruments; extract `Equatable` leaf views; precompute heavy state outside `body`. Compounds with §4.3 fan-out.
- **Severity:** Medium

### 7.4 Combine + `@MainActor` recalc fan-out
- **Location:** `StepsTrader/AppModel.swift` (CombineLatest recompute). Linked to §4.3 `@Observable` migration. **Severity:** Low.

### 7.5 Metal renderer reuses a static factory (no per-frame `CIContext`) — correct. **Severity:** Low (informational).

---

## 8. SwiftUI / UI

### 8.1 Oversized view files — see §9.2 for the split proposal
- **Location:** `OnboardingStoriesView.swift`, `GalleryView.swift`, `MeView.swift`, `CategoryDetailView.swift`, `EnergyGradientBackground.swift`. **Severity:** High (tracked under §9.2).

### 8.2 Hardcoded animation durations scattered across files
- **Location:** `OnboardingStoriesView.swift` (~25 occurrences), `GalleryView.swift` (~7), + others.
- **What:** `.animation(.easeInOut(duration: 0.8), value:)` with magic numbers.
- **Action:** Add `Utilities/AnimationDurations.swift` with named constants.
- **Severity:** Low

### 8.3 ✅ _RESOLVED — inline `endOfDay` moved to `DayBoundary.endOfCalendarDay`._

---

## 9. Dead code / duplication / refactor

### 9.1 ✅ _RESOLVED — `ProfileLocationManager` + root artifacts deleted._

### 9.2 Oversized files (>500 LOC) — refactor candidates (sizes re-measured 2026-06-01)
Category severity: **High** (testability + change risk).

- **`StepsTrader/Views/OnboardingStoriesView.swift` (1951 LOC)** — extract per-slide views into `Views/Onboarding/Slides/`; isolate analytics + gesture/navigation.
- **`StepsTrader/Views/GalleryView.swift` (1398 LOC)** — `CanvasToolbarState` / `CanvasEditState` view-models + loader manager + sub-views.
- **`StepsTrader/AppModel+DailyEnergy.swift` (1145 LOC)** — split into `+Snapshots`, `+Recovery`, `+Routines` / `+CanvasSlots`.
- **`StepsTrader/Views/MeView.swift` (908 LOC)** — extract `RadarLayout`, profile form, achievements.
- **`StepsTrader/Views/CategoryDetailView.swift` (885 LOC)** — extract `ActivityGridView`, `UsageBreakdownView`, `UnlockSheetView`.
- **`StepsTrader/Views/Components/EnergyGradientBackground.swift` (841 LOC)** — extract blob generation + opacity calc.
- **`UnlockWidget/UnlockWidgetViews.swift` (808)** + **`UnlockWidget/UnlockTimelineProvider.swift` (808)** — extract per-size views + `WidgetBudgetCompute`.
- **`StepsTrader/Services/AuthenticationService.swift` (805)** — already partially split (`+CachedProfile`, `+SupabaseREST`, `AuthSupportTypes`); further extract Apple-Sign-In + token management if touched.
- **`StepsTrader/Views/PaywallView.swift` (692)**, **`SettingsAppearancePage.swift` (660)** — borderline; split if touched.
- **Severity:** High
- **На практике:** Чтобы добавить слайд/блок/секцию — нужно орудовать в файле на 1000+ строк. Тесты на такие монолиты почти невозможны.

### 9.3 ✅ _RESOLVED — `OnboardingPreview` symlink documented in README._
### 9.4 ✅ _RESOLVED — 8 file-scope keys folded into `SharedKeys` (but see §5.12 for one missed site)._
### 9.5 ✅ _RESOLVED — wallpaper-shortcut URL moved to `AppConstants.URLs`._
### 9.6 `fatalError()` in unavailable Metal inits — intentional singleton-factory pattern. **Severity:** Low.

### 9.7 TODO/FIXME markers
- **Location:** repo-wide grep returns ~0 actionable `TODO`/`FIXME`/`HACK`/`#warning` in shipping code this pass (down from ~33 in the 2026-05-26 audit; sensoryFeedback bulk closed in §4.1).
- **Action:** None outstanding. **Severity:** Low (informational).

### 9.8 Magic constants that should be named — see §9.13 for the JPEG-quality instance. **Severity:** Low.
### 9.9 ✅ _RESOLVED — `OnboardingDemoView` prints DEBUG-gated._
### 9.10 ✅ _RESOLVED — marketing docs moved to `docs/marketing/`._
### 9.11 ✅ _RESOLVED — README "Domain vocabulary" section added._

### 9.12 Duplicate UserDefaults key constant — see §5.12
- Cross-referenced as a dead/duplicated-code item: `_payGateDismissedUntilKey` should be deleted in favor of `SharedKeys.payGateDismissedUntil`. **Severity:** Medium.

### 9.13 Inconsistent JPEG compression-quality magic constants
- **Location:** `StepsTrader/Intents/ExportCanvasWallpaperIntent.swift:199` (0.85), `StepsTrader/Views/ProfileEditorView.swift:269` (0.75), `StepsTrader/Services/CanvasStorageService.swift:143` (0.8)
- **What:** Three different `jpegData(compressionQuality:)` values across image-encode call sites with no shared constant.
- **Why:** Tuning image quality/size means hunting magic numbers; easy to make encodings inconsistent.
- **Action:** Add `enum ImageCompression { static let avatar = 0.75; static let canvas = 0.8; static let wallpaper = 0.85 }` and reference it.
- **Severity:** Low

### 9.14 Misspelled asset name `onboarding_figuer_1` ("figuer" → "figure")
- **Location:** `StepsTrader/Views/OnboardingStoriesView.swift:160-161`, `OnboardingPreview/Sources/Stubs.swift:197`, and the asset in `Assets.xcassets`.
- **What:** Asset name and its string references are misspelled.
- **Action:** Rename the asset to `onboarding_figure_1` and update all three references in lockstep.
- **Severity:** Low

### 9.15 `print()` not behind `#if DEBUG` in preview package
- **Location:** `OnboardingPreview/Sources/Stubs.swift:100` (`print("[Analytics] …")`)
- **What:** Unguarded `print` in the analytics stub.
- **Why:** Low impact — `OnboardingPreview` is a preview-only SPM package, not shipped in the app target. All `DeviceActivityMonitor` prints are correctly DEBUG-gated.
- **Action:** Wrap in `#if DEBUG` for consistency, or leave as preview-only.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Centralize App-Group state behind one coordinated store in `Shared/` (§5.2).** Multiple processes read/modify/write the same `UserDefaults(suiteName:)`. A typed `Shared/AppGroupStateStore` with `NSFileCoordinator` locking would make the contract explicit, testable, and race-safe. Highest-value open architectural item.
2. **Audit every UserDefaults key access against `SharedKeys` (§5.12, §9.12).** One duplicate slipped through the §9.4 consolidation; a quick grep for raw `"…_v1"` literals would catch the rest. Cross-process keys especially must have exactly one declaration.
3. **Migrate `ObservableObject` + `@Published` → `@Observable` (§4.3).** Unlocks finer-grained invalidation (mitigates §7.3/§7.4), removes Combine fan-out, prerequisite for `@Bindable`.
4. **Plan the Swift 6 strict-concurrency upgrade as one focused PR.** §3 is almost entirely latent — turn on strict concurrency on a branch, fix until clean, merge.
5. **Guard migration/cleanup paths so the source is only deleted after the destination write succeeds (§5.11).** The avatar bug is a one-off instance of a deletion-before-confirmed-write anti-pattern; grep for other `write(to:)` + unconditional `removeObject`/`removeItem` pairs.
6. **Keep enforcing `[weak self]` + `Task.isCancelled` as a review pattern** — the resolved §3.5/§3.6/§3.9/§5.3 family all traced to its absence.

---

## 11. What was NOT audited

- `admin-panel/` (Next.js), `tg-admin/` (Cloudflare Worker), `web/` — out of scope.
- Build settings / Xcode project structure beyond the shared scheme and `*.xcconfig` (one version-mismatch warning surfaced, §2).
- Third-party dependency internals — RevenueCat 5.x, Supabase JS treated as black boxes.
- `Steps4Tests/` / `Steps4UITests/` — light scan only.
- Algorithmic correctness of Metal kernels — surface checks only.
- Entitlements XML — see §6.7.
- StoreKit `.storekit` configuration — not opened.
- Localization correctness — not assessed.
- Instruments profiling — §7 perf items are potential, not trace-verified.
- A dedicated SwiftUI-expert pass was not separately re-run (recent `c5377a5` did one).
- `supabase/migrations/` SQL not audited beyond the §6.3 Edge Function.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line.

### Open / new findings — verified file:line this pass

- **§5.2** — `AppModel+PayGate.swift:85-96` confirmed: `defaults.integer(forKey:)` → `existingBudget + minutes` → `defaults.set(...)` with no cross-process coordination. Plus `BlockingStore`/`DeviceActivityMonitorExtension` JSON RMW. Test harness `Steps4Tests/AppGroupRMWConcurrencyTests` reproduces 50% loss (parked behind `XCTSkipIf`).
- **§5.11** — `AuthenticationService.swift:539-546` confirmed: `try legacyData.write(to:)` in a `do/catch` that only logs, followed by **unconditional** `UserDefaults.standard.removeObject(forKey: key)` at line 545.
- **§5.12** — confirmed: `AppModel+PayGate.swift:10` declares `_payGateDismissedUntilKey = "payGateDismissedUntil_v1"`; `SharedKeys.swift:59` declares the same literal; grep shows both in active use.
- **§5.13** — `SupabaseSyncService.swift:164-180` confirmed: `enqueueForRetry` appends + `suffix(maxRetryQueueSize)` with no `isExpired` filter.
- **§9.2** — sizes re-measured via `wc -l` 2026-06-01 (1951 / 1398 / 1145 / 908 / 885 / 841 / 808 / 808 / 805 / 692 / 660).
- **§9.13 / §9.14** — JPEG-quality literals and `figuer` references confirmed by grep at the cited lines.
- **§6.1** — RESOLVED: `Config/Secrets-Debug.xcconfig` / `Secrets-Release.xcconfig` layers + Release host assertion in `NetworkClient.swift`.

### Demotions from agent-flagged Critical (this run)

- **"Data race on `lastStepCount` in `fetchSteps` closure"** (Agent A, Critical) — **DROPPED.** `lastStepCount` is a computed property whose get/set both take `_stepCountLock` (`HealthKitService.swift:43-48`); the closure accesses go through the lock. The only residual is the latent Swift-6 off-actor `self` capture (covered by §3).
- **"App-Group budget RMW = data loss"** (Agent C, Critical) — **DEMOTED to High**, folded into §5.2. Same root cause as the existing High finding; individual writes are atomic and the collision window is narrow.
- **"Unchecked `prefix(4)` drops slots"** (Agent C, High) — **DROPPED.** `AppModel+DailyEnergy.swift:277-280` runs a `while slots.count < 4` fill loop immediately before `Array(slots.prefix(4))`, so the count is guaranteed ≥ 4 — defensive, not a bug.
- **"`initialFetchTask = nil` is dead code on cancel"** (Agent C, High) — **DROPPED.** Line 412 runs on normal completion; external cancellation is handled by `initialFetchTask?.cancel()` at line 386 on re-entry. No leak.
- **"Timer reschedule not on MainActor"** (Agent A, Critical) — **DEMOTED to Low** (§3.12). The closure hops to `@MainActor` via `Task`.

If any finding doesn't reproduce when you visit the line, flag the specific reference and it'll be re-investigated.
