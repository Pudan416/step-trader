# Nowhere (StepsTrader) Code Audit

Generated 2026-05-26. Scope: ~52,000 LOC across 219 Swift files + 3 Metal kernels across 7 targets (Steps4, DeviceActivityMonitor, ShieldConfiguration, ShieldAction, UnlockWidgetExtension, Steps4Tests, Steps4UITests). The local SPM package `OnboardingPreview` is included. `admin-panel/`, `tg-admin/`, `web/`, `build/`, `output/`, `tmp/`, `docs/`, and `Scripts/` are excluded.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

A clean Debug build of the `Steps4` scheme against iPhone 17 (iOS 26.1) produced **one** compiler warning. The codebase compiles in Swift 5 mode without strict-concurrency enabled, so most concurrency findings below are latent — they'll begin to fire when the project upgrades to Swift 6 / `SWIFT_STRICT_CONCURRENCY=complete`. Treat them as preparatory work for that migration.

There are **no Critical findings** in this audit. Several Agent-flagged "Critical" items were demoted during verification (see §12) because the code was already correctly isolated, the failure mode wasn't reachable, or the safety claim turned out to be inverted. That's a reflection of recent hygiene work — `git log` shows the SwiftUI-pro review fixes landed on this branch — not absence of audit.

The prior PR-scoped audit was preserved at `CODE_AUDIT_PR_moment.md` so this file can carry the full-project findings without losing that earlier context.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] Dead service `ProfileLocationManager` (118 LOC) with zero references** — §9.1 — `StepsTrader/Services/ProfileLocationManager.swift`. CoreLocation permissions noise + dead code.
2. **[High] `UnsafeSendableBox` (`@unchecked Sendable`) used to bridge the HK auth-timeout pattern** — §3.2 — `StepsTrader/Services/HealthKitService.swift:29-32`. Will fail Swift 6 strict mode and is a real data-race surface if the timeout races a resume.
3. **[High] PayGate monitoring failure refunds silently with no UI feedback** — §5.1 — `StepsTrader/AppModel+PayGate.swift:101-110`. User is charged, then refunded, but the PayGate sheet stays up showing the same balance — confusing flow that masks a real DeviceActivity error.
4. **[High] No Debug/Release Supabase URL split — single `Secrets.xcconfig` shared by both** — §6.1 — `Config/Debug.xcconfig`, `Config/Release.xcconfig`. Both configs `#include "Secrets.xcconfig"`; staging/dev data lands in the prod database (or vice-versa) depending on whose secrets are on disk.
5. **[High] 24 outstanding "Migrate to .sensoryFeedback()" TODOs across the UI** — §4.1. A planned but never-completed migration; ship it as one cleanup or remove the TODOs.
6. **[High] Oversized SwiftUI views (1974 / 1657 / 1119 LOC) couple state, network, and rendering** — §9.2 — `OnboardingStoriesView.swift`, `GalleryView.swift`, `MeView.swift`. Hard to test, slow to change.
7. **[High] App-Group `UserDefaults` read-modify-write between app and DeviceActivity extension is unsynchronized** — §5.2 — `BlockingStore.swift:87-93` + `DeviceActivityMonitorExtension.swift:172-192`. Individual reads/writes are atomic; compound mutations aren't.
8. **[High] `UNUserNotificationCenter.add(_:withCompletionHandler:)` completion handlers run on an undefined thread and call shared loggers** — §3.3 — `NotificationManager.swift:35-42, 57-64, 79-86, 112-119`. Async overload exists on iOS 17.
9. **[High] Unused HealthKit observer/initial-fetch task is not stored, so `stopObservingSteps()` cannot cancel an in-flight initial fetch** — §5.3 — `HealthKitService.swift:385-410`. Late-arriving fetch can re-prime `lastStepCount` after observation was deliberately stopped.
10. **[Medium] One canonical compiler warning** — §4.2 — `AuthenticationService.swift:403`: `no 'async' operations occur within 'await' expression`. Either drop the `await` or restructure the post-login Task.

---

## 2. Quick wins (≤30 min each)

These deliver outsized value relative to effort and have no architectural ripples.

- **Delete `StepsTrader/Services/ProfileLocationManager.swift`** — `Services/ProfileLocationManager.swift:1-118`. Zero references; ~120 LOC removed and one fewer permission API surface to audit.
- **Delete `test.txt` and `icon_gen_output.txt` at repo root** — both look like accidental commits; `test.txt` contains "hello".
- **Remove the single compiler warning** — `Services/AuthenticationService.swift:403` — drop the `await` in front of `self?.postLoginSyncModel` (or restructure that line if the property has changed type).
- **Consolidate the 8 private `_dailyEnergy…Key` constants into `SharedKeys`** — `AppModel+DailyEnergy.swift:5-13`. The comment at line 5 ("file-scope to avoid `@MainActor` isolation on static lets") is no longer load-bearing; `SharedKeys` is a `nonisolated enum`.
- **Add `[weak self]` guards (or `Task.isCancelled`) to short Combine `sink` tasks** — `AppModel.swift:251-255`. Pattern repeats; one-line fix per call site.
- **Move marketing-only Markdown out of repo root into `docs/marketing/`** — `BRANDBOOK.md`, `MARKETING_COMPETITOR_RESEARCH.md`, `ARTICLE_BLOG.md`, `POSITIONING_ANGLES_SKILL.md`, `TONE_OF_VOICE.md`, `MANUALS_TEXTS.md`. Repo-root clutter, not code risk.
- **Add `*.txt` and `icon_gen*.txt` to `.gitignore`** to prevent re-introducing root artifacts.
- **Wrap or remove the 4 `print()` calls in `OnboardingDemoView.swift`** behind `#if DEBUG`. Demo-only views still ship in Release.

---

## 3. Concurrency

The project compiles in Swift 5 mode without strict concurrency. The single canonical warning is in §4.2. Everything below is **latent** — it'll surface when the project flips on `SWIFT_STRICT_CONCURRENCY=complete` or upgrades to Swift 6 language mode. Triage these in advance of that upgrade rather than treating them as live bugs.

### 3.1 Post-login Task fans out from a `@MainActor`-isolated context without checking `Task.isCancelled` between awaits
- **Location:** `StepsTrader/Services/AuthenticationService.swift:399-408`
- **What:** A nested `Task { [weak self] in … }` is spawned from an already-`@MainActor` context; `Task.isCancelled` is checked once after `SubscriptionStore.shared.logIn(…)` but not between subsequent awaits. The outer wrapper `Task { @MainActor in … }` at line 347 is also redundant — `handleAuthorization` is already on the main actor by class annotation.
- **Why:** Cancellation only takes effect at the one checkpoint; a sign-out racing with sign-in can leave a stale full-sync running against the wrong user.
- **Action:** Add `guard !Task.isCancelled else { return }` after each `await`, and drop the redundant `Task { @MainActor in … }` wrapper at line 347 once the method is confirmed `@MainActor`-isolated. Treat the inner Task as the cancellation handle.
- **Severity:** Medium

### 3.2 `UnsafeSendableBox` (`@unchecked Sendable`) bridges the auth-timeout race
- **Location:** `StepsTrader/Services/HealthKitService.swift:29-32`, used 108-128
- **What:** A class marked `@unchecked Sendable` wraps a mutable `Bool` so the manual 10-second timeout can flip a flag from a `Task.detached` and the original continuation can read it. The two writers are not synchronized.
- **Why:** Bypasses the Sendability checker and is a textbook data race (two concurrent `value =` and `value` reads with no lock). The whole timeout dance also exists to work around a hang that the modern async `HKHealthStore.requestAuthorization(toShare:read:)` overload doesn't have.
- **Action:** Replace the box with `OSAllocatedUnfairLock<Bool>` *or*, preferred, delete the timeout wrapper and call the async overload directly. The "did the dialog appear" failure mode is rarely worth the complexity it adds here.
- **Severity:** High

### 3.3 `UNUserNotificationCenter.add(_:withCompletionHandler:)` completion handlers run on an undefined thread
- **Location:** `StepsTrader/NotificationManager.swift:35-42, 57-64, 79-86, 112-119` (~7 call sites by grep)
- **What:** Every notification add uses the completion-based overload; the handler calls `AppLogger.notif.…` (shared OS log state) with no thread guarantee.
- **Why:** Logger writes are individually safe, but on Swift 6 the closure-passing-non-Sendable-self pattern will error. The async overload `try await UNUserNotificationCenter.current().add(request)` has existed since iOS 16 and resolves both issues.
- **Action:** Replace all `add(_:withCompletionHandler:)` call sites with the async overload, log inside the awaiting context, and bubble errors through `do/catch`.
- **Severity:** High

### 3.4 `SupabaseSyncService` is an actor but exposes a `nonisolated static let shared`
- **Location:** `StepsTrader/Services/SupabaseSyncService.swift:6-8`
- **What:** The actor pattern is correct, but `nonisolated static let shared = SupabaseSyncService()` exposes the actor as a singleton accessible from any context. That's fine in itself (the access is `await`-gated on each method call), but it normalizes "just call shared from anywhere," which on Swift 6 obscures whether the call point is properly suspending.
- **Why:** Singleton + actor is well-defined, but callers occasionally forget the `await` and the compiler only catches that in strict mode.
- **Action:** Keep the singleton but audit call sites once strict-concurrency lands. Convert truly thread-safe pure helpers (formatters, key builders) to `nonisolated` so they can be called without `await`.
- **Severity:** Medium

### 3.5 Combine `sink` closures spawn untracked `Task` blocks
- **Location:** `StepsTrader/AppModel.swift:251-255` (CombineLatest → recalc), `StepsTrader/Stores/SubscriptionStore.swift:129-133` (`customerInfoStream` listener), plus several other sites following the same pattern
- **What:** Each sink does `Task { @MainActor in self?.… }` without storing the Task handle, so the closure cannot be cancelled when the model is torn down or reconfigured.
- **Why:** On `DIContainer` recreate (debug live-reload, tests that reset state), prior tasks continue running with stale `[weak self]` captures, occasionally firing on a phantom instance. In Swift 6, the implicit capture of an `@MainActor` model in an unbounded Task will warn.
- **Action:** Promote these to stored `Task<Void, Never>?` properties or `Set<Task<Void, Never>>` and cancel them in `deinit` / on reconfigure. Pair each `await` with `guard !Task.isCancelled else { return }` before touching mutable state.
- **Severity:** Medium

### 3.6 `HKObserverQuery` re-fetch task ignores its lifetime
- **Location:** `StepsTrader/Services/HealthKitService.swift:446-469`
- **What:** The observer's completion handler `[weak self]`-guards correctly and dispatches into a `Task { … }`, but the Task is not stored. If `stopObservingSteps()` runs while a `fetchSteps()` is in flight, the late callback still writes to `lastStepCount` and pushes a stale value through `updateHandler`.
- **Why:** The lock around `_stepCountLock` keeps the write atomic, but the *value* being pushed is from the moment the observer fired, not the moment the user expected observation to end.
- **Action:** Store the in-flight Task; cancel it in `stopObservingSteps()` before nilling `observerQuery`. Or check `isObserving` inside the Task before pushing the update.
- **Severity:** Medium

### 3.7 Diagnostic `Task.detached` in `fetchSteps` is fire-and-forget
- **Location:** `StepsTrader/Services/HealthKitService.swift:243-265`
- **What:** A debug-only sample-source breakdown query runs on every `fetchSteps` via `Task.detached` with no cancellation, no completion signal, and no `#if DEBUG` guard.
- **Why:** Each call doubles the HealthKit query traffic; on a HealthKit-heavy session the detached tasks can pile up. Also fires in Release builds.
- **Action:** Either guard the whole block with `#if DEBUG`, or convert to a single throttled diagnostic that runs at most once per minute.
- **Severity:** Medium

### 3.8 `DeviceActivityMonitor` extension callbacks call `ShieldRebuildHelper.rebuild()` on the system-chosen thread
- **Location:** `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift:148-160, 158-306` (intervalDidStart / eventDidReachThreshold paths)
- **What:** Extension lifecycle methods call into `Shared/ShieldRebuildHelper.rebuild()` which touches `ManagedSettingsStore(named: …)`. `ManagedSettingsStore` is thread-safe in practice but is not documented as `Sendable` and the helper is not annotated.
- **Why:** Works today. Under strict concurrency, calling a non-`Sendable` API from an unknown actor context will warn or error. Worth noting because the extension is a separate process with no `@MainActor` to fall back on.
- **Action:** Make `ShieldRebuildHelper` a fileprivate-state-free enum with explicitly `Sendable`-friendly inputs/outputs, and document the threading contract in the file header.
- **Severity:** Medium

### 3.9 Initial-fetch and observation start are not ordered against each other
- **Location:** `StepsTrader/Services/HealthKitService.swift:396-409`
- **What:** Inside `startObservingSteps`, an unguarded `Task { [weak self] in … }` does `fetchSteps(...)` then `beginObservation(...)`. If `stopObservingSteps()` is invoked between the two awaits, observation will still start.
- **Why:** Leaves a live `HKObserverQuery` after the caller has logically stopped observing, defeating teardown.
- **Action:** Store this Task on the service; cancel it in `stopObservingSteps()`. After each `await`, `guard !Task.isCancelled else { return }`.
- **Severity:** Medium

### 3.10 `BlockingStore` post-debounce Task does not check cancellation
- **Location:** `StepsTrader/Stores/BlockingStore.swift:68-76`
- **What:** Selection-change debounce uses `Task.sleep` followed by self-mutation, with no `Task.isCancelled` check after the sleep.
- **Why:** If the debounce is replaced by a newer selection change, the older Task still mutates `appSelection`, overwriting the newer state.
- **Action:** `guard !Task.isCancelled else { return }` after the sleep, before any self mutation.
- **Severity:** Medium

### 3.11 `UIWindowScene.windows` accessed directly
- **Location:** `StepsTrader/Views/Onboarding/AppleSignInCoordinator.swift` (presentation anchor lookup) and `StepsTrader/Stores/SubscriptionStore.swift:323-330`
- **What:** Code reaches for `scene.windows.first` to find a presentation anchor.
- **Why:** Works, but the connected-scenes pattern is the documented one for multi-scene iPad and future split-screen / external display support.
- **Action:** `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }?.windows.first { $0.isKeyWindow }`.
- **Severity:** Low

### 3.12 `Timer.scheduledTimer` callback for the day-boundary check
- **Location:** `StepsTrader/AppModel.swift:344-355`
- **What:** Timer block correctly hops to `Task { @MainActor [weak self] in … }`, so the live concurrency hazard Agent A flagged is not present. The remaining issue: `[weak self]` is double-captured (outer + inner) and the recursive re-schedule silently stops if `self` is nil between fires.
- **Why:** Harmless under current ownership (`AppModel` lives for the app lifetime), but easy to break under DI reset in tests.
- **Action:** Replace with an `AsyncStream` driven by `DayBoundary.nextBoundary(…)` + `Task.sleep(until:)` and an explicit cancel in `deinit`. Or accept the current pattern and add a comment that lifetime equals app lifetime.
- **Severity:** Low

---

## 4. API modernity

### 4.1 24 outstanding `// TODO: Migrate to .sensoryFeedback()` markers
- **Location:** Across `CategoryDetailView.swift`, `PaywallView.swift`, `OnboardingStoriesView.swift`, `InlineTicketSettingsView.swift`, `AppsPageSimplified.swift`, `GalleryView.swift`, `SettingsAppearancePage.swift` (x8), `SettingsSubscriptionPage.swift` (x2), `SettingsWidgetPage.swift`, `SmudgeCanvasView.swift`, `PaperTicketView.swift` (x2), `WorkoutSuggestionBanner.swift`, `StepGoalDrumPicker.swift` (x3), `SleepGoalArcPicker.swift` (x3), `ShaderParkOverlayView.swift`. Total 24 sites.
- **What:** UIKit `UIImpactFeedbackGenerator` / `UISelectionFeedbackGenerator` calls flagged for migration to SwiftUI's native `.sensoryFeedback` modifier (iOS 17+).
- **Why:** `.sensoryFeedback` integrates with SwiftUI's update model, is testable, respects accessibility settings, and avoids the UIKit bridge per haptic call.
- **Action:** One bulk migration PR — convert all 24 in a single sweep, delete the TODOs. The mechanical pattern is small enough to script.
- **Severity:** High

### 4.2 Single compiler warning — vestigial `await` in post-login task
- **Location:** `StepsTrader/Services/AuthenticationService.swift:403`
- **What:** `if let appModel = await self?.postLoginSyncModel` — `postLoginSyncModel` is a stored `weak var`, so the property access doesn't suspend.
- **Why:** Only build warning in a clean `Steps4` build. Likely an artifact of an earlier signature.
- **Action:** Drop the `await`. If a re-typing makes it actually `async`, restructure the block to capture the snapshot once at the top.
- **Severity:** Medium

### 4.3 `@Published` + `ObservableObject` still used where `@Observable` would do
- **Location:** `StepsTrader/AppModel.swift:18-20`, every file in `StepsTrader/Stores/*.swift`, `AuthenticationService.swift:62-63`
- **What:** Stores and services declare `@MainActor final class … : ObservableObject` with `@Published` properties. Deployment target is iOS 17.5, so `@Observable` is supported.
- **Why:** `@Observable` removes the `Combine` dependency for state propagation, gives finer-grained dirty tracking (re-renders only what actually changed), and removes the `@StateObject` / `@ObservedObject` distinction at the call site.
- **Action:** Migrate incrementally — `AppModel` and its 13 extensions are the biggest payoff. Stores can follow. Defer if iOS 17.5 support for `@Observable` macro has any edge cases you've hit, but on a clean 17.5 floor it's straightforward.
- **Severity:** Medium

### 4.4 `withCheckedThrowingContinuation` wraps HealthKit calls that have async overloads
- **Location:** `StepsTrader/Services/HealthKitService.swift:108-128` (requestAuthorization), `:162-207` (fetchSleep)
- **What:** `HKHealthStore.requestAuthorization(toShare:read:)` has an async overload since iOS 15.4. `HKSampleQuery` does not have a direct async overload, but the existing continuation wrapper is structurally fine — the auth one is the live opportunity.
- **Why:** The continuation wrapper for `requestAuthorization` exists only to bolt on the manual 10-second timeout (see §3.2). The async overload itself doesn't hang on modern iOS.
- **Action:** Use the async overload for auth; delete the timeout box. Leave the `HKSampleQuery` wrapper as-is or convert to `AsyncThrowingStream` if a future feature wants progressive results.
- **Severity:** Medium

### 4.5 Push add — see §3.3
- **Location:** see §3.3.
- **What:** Same as §3.3, repeated here so the modernity opportunity is independently trackable.
- **Why:** Async overload is the canonical post-iOS-16 pattern.
- **Action:** Migrate per §3.3.
- **Severity:** Medium

### 4.6 No `@available(iOS X, *)` guards below the deployment target found
- **Location:** N/A
- **What:** Grep for `@available(iOS` against deployment target 17.5 turned up only forward-looking guards (`iOS 16.0` in `HealthKitService.swift:182` for `HKCategoryValueSleepAnalysis.asleepCore`, which is a real iOS 16+ symbol still relevant here).
- **Why:** No cleanup opportunity here.
- **Action:** None.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 PayGate refund leaves the UI in a confused state when DeviceActivity monitoring fails
- **Location:** `StepsTrader/AppModel+PayGate.swift:101-110`
- **What:** When `startUsageBudgetMonitoring(...)` returns `false`, the code refunds, clears the budget keys, and returns. The PayGate sheet stays up, the balance display now matches pre-payment, and no toast / error is shown.
- **Why:** From the user's perspective they just confirmed a purchase, watched the balance bounce back, and got no feedback explaining why nothing unlocked. They'll retry; the same failure repeats. The underlying DeviceActivity error never surfaces.
- **Action:** Set a user-visible error (`@Published var payGateError: PayGateError?`), dismiss the sheet on failure, and log the underlying reason from `startUsageBudgetMonitoring` so support can correlate. Optionally retry once before showing the error.
- **Severity:** High

### 5.2 App-Group `UserDefaults` compound mutations are not synchronized between app and DeviceActivity extension
- **Location:** `StepsTrader/Stores/BlockingStore.swift:87-93` (app side writes `appSelection`), `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift:172-192, 263-294` (extension reads + writes budget keys)
- **What:** Each individual `set` / `data(forKey:)` on `UserDefaults(suiteName:)` is atomic, but the app and extension perform compound read-modify-write sequences (load → decode JSON → mutate → re-encode → set) with no cross-process coordination.
- **Why:** When the extension fires at a time-budget threshold while the app is mid-save, the extension can resurrect a stale `appSelection`. The window is narrow but the resulting state is sticky (a shield rebuild based on stale tokens).
- **Action:** Move the compound state to a file lock (`NSFileCoordinator` with the App Group container) or, simpler, serialize ALL App-Group writes through a single `AppGroupStateStore` actor that lives in `Shared/` and is consumed from both processes. For mutually-exclusive ownership (e.g., budget state owned by extension), document who writes each key.
- **Severity:** High

### 5.3 Initial HealthKit fetch can write past `stopObservingSteps()`
- **Location:** `StepsTrader/Services/HealthKitService.swift:385-410`
- **What:** Cross-reference of §3.9 from a bug-impact angle: `startObservingSteps` kicks off an initial fetch as an untracked task. If `stopObservingSteps()` is called before the fetch returns, the fetch still writes `lastStepCount` and calls `updateHandler`, pushing data into a UI that thinks observation is off.
- **Why:** Real UX impact for `signOut` → `signIn` flows where the prior user's step count briefly appears for the new session.
- **Action:** See §3.9 — store and cancel the initial-fetch Task.
- **Severity:** High

### 5.4 Day-boundary recompute can run with stale `dayEndHour` / `dayEndMinute` if the user changes them during the recompute
- **Location:** `StepsTrader/AppModel+DailyEnergy.swift:36-38`, `StepsTrader/AppModel.swift:284-315`
- **What:** `currentDayStart(for:)` and `isSameCustomDay` read `@Published var dayEndHour/Minute`. If a settings sheet writes those properties while a recompute is in flight (Combine debounce, see §3.5), part of the recompute uses the old boundary and part uses the new.
- **Why:** Manifests as the canvas snapping to an unexpected day for ~1 frame. Persisted state is recoverable but the transient looks like a bug to users.
- **Action:** Snapshot `(dayEndHour, dayEndMinute)` once at the top of any recompute, pass it down. Or move boundary computation into `DayBoundary` static methods that take explicit parameters (mostly already done — finish the migration).
- **Severity:** Medium

### 5.5 _RESOLVED 2026-05-26: Moment IDs now filtered at every Supabase sync boundary._

Original finding (now fixed): the local-only Moment feature was leaking `moment_<uuid>` IDs to `user_day_snapshots.body_ids/mind_ids/heart_ids` and `user_daily_selections.activity_ids/rest_ids/joys_ids`. The label was never sent, so a second device — or a fresh install restoring from server — would see opaque `moment_abc123` strings in `MeView` history (`resolveOptionTitle` fell back to the raw ID).

What changed:
- `StepsTrader/Models/EphemeralMoment.swift` — header rewritten to document the local-only contract; centralized `idPrefix` constant and added `isMomentId(_:)` / `filteredOutOfSync(_:)` helpers as the single source of truth.
- `StepsTrader/AppModel+DailyEnergy.swift` — `resolveOptionTitle` now uses `EphemeralMoment.isMomentId(_:)` (no more inline `hasPrefix("moment_")`); `saveCurrentAsRoutine` strips moment IDs before persisting (a one-time event has no place in a reusable template).
- `StepsTrader/Services/SupabaseSyncService+Stats.swift` — `performDaySnapshotSync` strips moment IDs from `bodyIds`/`mindIds`/`heartIds` before upsert; `loadDaySnapshotsFromServer` and `loadHistoricalSnapshots` strip on the way in to scrub any stale rows written before this fix.
- `StepsTrader/Services/SupabaseSyncService+Selections.swift` — `performDailySelectionsSync` strips moment IDs from the upsert payload.

Existing UI copy in `MomentEntrySheet.swift:69` ("Just for today, on this device.") now matches the actual data contract — moments never cross the device boundary.

Cross-device persistence remains a separate feature (would need a `moments` JSONB column on `user_day_snapshots`, restore + merge logic, and conflict resolution for the same user logging moments on two devices). Tracked as a follow-up; not in scope for the `feature/moment-ephemeral-activity` PR.

- **Severity:** Medium → **Resolved**

### 5.6 Keychain migration silently keeps a UserDefaults shadow on Keychain failure
- **Location:** `StepsTrader/Services/AuthenticationService.swift:629-639`
- **What:** One-time migration writes the legacy `UserDefaults` session to Keychain. On Keychain failure, it logs but keeps the `UserDefaults` copy. Subsequent `loadStoredSession` reads from Keychain only (`SessionKeychain.loadSession()`), so the kept-as-fallback `UserDefaults` blob is never read — it just lingers indefinitely.
- **Why:** The "fallback" is misleading: it's not actually consulted on the next launch. Real-world failure modes (locked Keychain on device boot before first unlock) will result in the user being signed out even though the legacy data is still present.
- **Action:** Either (a) make `loadStoredSession` fall back to UserDefaults if Keychain returns nil but the legacy key exists, or (b) accept the sign-out, delete the legacy UserDefaults blob, and surface a re-auth prompt. The current half-measure is worse than either extreme.
- **Severity:** Medium

### 5.7 Deep-link `bundleId` is passed unvalidated to `TargetResolver`
- **Location:** `StepsTrader/StepsTraderApp.swift:463-474`
- **What:** `handleWidgetOpenApp` pulls `bundleId` from `URLComponents` query and feeds it straight into `TargetResolver.primaryAndFallbackSchemes(for:)`. Whatever the resolver returns is opened.
- **Why:** The risk surface is small (resolver returns an allow-list; unmapped IDs → empty schemes), but the value flows through logging unredacted. A malicious widget configuration could log attack patterns to a remote sink.
- **Action:** Validate `bundleId` against a strict reverse-DNS regex before the resolver call. Log the validated form only.
- **Severity:** Low

### 5.8 `attemptOpenScheme` recursion after `UIApplication.shared.open` callback uses `Task { @MainActor in self?.attemptOpenScheme(…) }`
- **Location:** `StepsTrader/HandoffManager.swift:79-89`
- **What:** Recursive scheme fallback. Each step bounces back to `@MainActor` via a new Task. Works, but means the recursion is asynchronous and a rapid second open call can interleave with a pending attempt.
- **Why:** Two simultaneous handoffs (very rare) would race; second writes `lastAppOpenedFromStepsTrader` after the first.
- **Action:** Guard against re-entrancy with a `currentlyOpening` flag, or coalesce by `bundleId`.
- **Severity:** Low

### 5.9 `merged[merged.count - 1]` in sleep-merge logic
- **Location:** `StepsTrader/Services/HealthKitService.swift:213-225`
- **What:** Algorithm correctness OK (`guard !intervals.isEmpty` precedes the indexed access). Reads as fragile because `merged.count - 1` could underflow in a future refactor.
- **Why:** Defensive style; not a live bug.
- **Action:** Replace with `if var last = merged.last { … merged[merged.count - 1] = last }` pattern, or use `inout` view into `merged.last`.
- **Severity:** Low

### 5.10 Recursive timer rescheduling silently stops on `self == nil`
- **Location:** `StepsTrader/AppModel.swift:344-355`
- **What:** If `self?.scheduleDayBoundaryTimer()` fires when `self` has been deallocated (test reset), the timer chain ends with no log.
- **Why:** Tests that swap `AppModel` instances may observe missing day-boundary callbacks for the new instance.
- **Action:** Add a guard log at the start of the closure; or move day-boundary work to an `AsyncStream` that lives only as long as the model.
- **Severity:** Low

---

## 6. Security

### 6.1 No Debug/Release split for Supabase credentials
- **Location:** `Config/Debug.xcconfig`, `Config/Release.xcconfig` (both `#include "Secrets.xcconfig"`)
- **What:** Both Debug and Release configurations include the same `Secrets.xcconfig`, which sets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `REVENUECAT_API_KEY` to a single value. There is no environment isolation between debug and release builds.
- **Why:** A staging Supabase project is impossible without overwriting prod secrets, and dev work touches the production database by default. This isn't the "release ships dev URL" failure mode (the values are identical at compile time), but it removes the safety net that having two environments provides.
- **Action:** Split `Secrets.xcconfig` into `Secrets-Debug.xcconfig` and `Secrets-Release.xcconfig` and have `Debug.xcconfig` / `Release.xcconfig` include the correct one. Add a compile-time assertion (or a runtime check on first launch) that the URL host matches an expected production domain in Release builds.
- **Severity:** High

### 6.2 No hardcoded secrets in client code
- **Location:** Repo-wide grep over `Bearer`, `apiKey`, `service_role`, `SUPABASE_SERVICE`, base64 blobs ≥32 chars
- **What:** All `Bearer …` strings are followed by `token` / `session.accessToken` / `cfg.anonKey` (i.e., values pulled from the validated session or Info.plist). The Supabase anon key is intentionally client-shipped. The RevenueCat key is also a public client key (prefix `appl_`).
- **Why:** Confirms the layer is correctly modeled — only public keys reach the client; service-role only lives in the Edge Function.
- **Action:** Document this contract in `README.md` so future contributors don't accidentally put a service-role key in `Secrets.xcconfig`.
- **Severity:** Low

### 6.3 `supabase/functions/send-push/index.ts` is well-hardened
- **Location:** `supabase/functions/send-push/index.ts:1-275`
- **What:** Verified during audit: env-var `requireEnv`, constant-time bearer compare against `SUPABASE_SERVICE_ROLE_KEY`, CORS closed, narrow APNs cleanup heuristic (only `BadDeviceToken` / `Unregistered` delete tokens, `DeviceTokenNotForTopic` logged but not cleaned), error responses don't leak which case failed.
- **Why:** No security finding; this is a model the rest of the project's server-side code should mirror.
- **Action:** None. Use this file as the template if other Edge Functions are added.
- **Severity:** Low

### 6.4 Handoff token is locally generated and locally verified — by design
- **Location:** `StepsTrader/Models/HandoffToken.swift:1-13`, consumed at `StepsTrader/StepsTraderApp.swift:476-518`
- **What:** `HandoffToken` is created by an extension (e.g., `ShieldAction`) and read by the main app. `isExpired` is computed entirely client-side from `createdAt + AppConstants.Timing.handoffTokenExpiry`.
- **Why:** Agent C flagged this as forgeable; in practice the token is local-only — same device, same user, no privilege boundary being crossed. A user who tampers with their own UserDefaults can already do anything the extension can. No server-side validation is needed.
- **Action:** Document the trust model in `HandoffToken.swift` so the design isn't second-guessed in a future audit.
- **Severity:** Low

### 6.5 Retry queue stores raw request bodies without integrity check
- **Location:** `StepsTrader/Services/SupabaseSyncService.swift:164-179`
- **What:** Offline retry queue persists `URLRequest` bodies via `UserDefaults` JSON, with no checksum/HMAC. A corrupted entry replays as a malformed request.
- **Why:** Real-world corruption is rare; the failure mode is graceful (server returns 4xx, entry is dropped). Mostly belt-and-suspenders.
- **Action:** Optional — add a CRC of the payload to the persisted envelope and skip entries whose CRC doesn't match on drain.
- **Severity:** Low

### 6.6 Print/log redaction
- **Location:** `StepsTrader/Services/AuthenticationService.swift` throughout
- **What:** Log lines that touch session data use `…prefix(8))…` to truncate user IDs and don't print raw access tokens. Spot-checked across `loadStoredSession`, `signIn`, `signOut`, post-login. Apple Logger debug/info levels do not persist to disk by default.
- **Why:** Good hygiene — confirms tokens/emails don't leak into logs.
- **Action:** None. Worth keeping the pattern.
- **Severity:** Low

### 6.7 Entitlements files were not opened
- **Location:** `Steps4/Steps4.entitlements`, `UnlockWidgetExtensionRelease.entitlements`, shield extension entitlements
- **What:** Audit confined to Swift / config files; the entitlements XML was not parsed in this run.
- **Why:** Listed under §11 to be explicit.
- **Action:** Confirm separately that the App Group `group.personal-project.StepsTrader` is present on every target that needs it (DeviceActivityMonitor, ShieldAction, ShieldConfiguration, UnlockWidgetExtension).
- **Severity:** Low

---

## 7. Performance

### 7.1 Diagnostic detached query doubles HealthKit traffic per fetch
- **Location:** `StepsTrader/Services/HealthKitService.swift:243-265`
- **What:** Each `fetchSteps` fires a second `HKSampleQuery` (limit 200) purely for source-breakdown logging, in a `Task.detached` with no rate limiting.
- **Why:** On a HealthKit-active session (observer fires every few minutes), this doubles query load for no shipped feature.
- **Action:** Wrap in `#if DEBUG` or rate-limit to once per minute. See §3.7.
- **Severity:** Medium

### 7.2 Widget timeline provider does substantial work per entry
- **Location:** `UnlockWidget/UnlockTimelineProvider.swift:1-791`
- **What:** Snapshot + timeline computation reads App-Group keys, decodes ticket groups, computes per-locale strings, formats budget remaining. Runs every refresh.
- **Why:** Widget refresh budget is limited and shared with all of WidgetKit. Heavy timeline-provider work is a battery / energy concern in the long tail.
- **Action:** Extract a `WidgetBudgetCompute` value type with explicit inputs; cache locale-aware formatters at module scope (`static let`); make the timeline entry as small as possible. Verify with Instruments on a real device that any change actually moves the needle.
- **Severity:** Medium

### 7.3 Hot SwiftUI views recompute heavy state in body
- **Location:** `StepsTrader/Views/GalleryView.swift:1-1657`, `StepsTrader/Views/MeView.swift:1-1119`, `StepsTrader/Views/CategoryDetailView.swift:1-900`
- **What:** Large body functions compute layout, sort, format, and render in one pass without obvious memoization. Detailed assessment was not done (no Instruments trace), but file size and `body` structure suggest extraction opportunities.
- **Why:** Frequent re-renders from `@Published` changes cascade through these views.
- **Action:** Profile with SwiftUI Instruments first; then extract leaf views with explicit `Equatable` conformances and move heavy computation into precomputed view-model properties. See §9.2 for the structural split.
- **Severity:** Medium

### 7.4 Combine + `@MainActor` recalc fan-out
- **Location:** `StepsTrader/AppModel.swift:243-256`
- **What:** Every store's `objectWillChange` fans out via sink into `AppModel.objectWillChange.send()`. A single step-count update therefore invalidates the entire `AppModel`-observing view tree, not just step-dependent views.
- **Why:** With `ObservableObject`, granular invalidation isn't possible — this is the standard pattern. With `@Observable` (see §4.3) the fan-out can be replaced with finer dependency tracking.
- **Action:** Linked to the `@Observable` migration in §4.3 — there's no improvement without that base change.
- **Severity:** Low

### 7.5 No fresh `CIContext` per-frame; Metal renderer uses static factory
- **Location:** `StepsTrader/Metal/MetalSmudgeRenderer.swift:140-160`, `StepsTrader/Metal/MetalShaderParkRenderer.swift`
- **What:** Renderers are constructed via static factory once and reused; no per-frame `CIContext()` allocations that Agent C might flag in a typical iOS app.
- **Why:** Confirms the rendering pipeline is correctly amortized.
- **Action:** None.
- **Severity:** Low

---

## 8. SwiftUI / UI

A dedicated SwiftUI pass was not re-run for this audit — `git log` shows commit `c5377a5 refactor: apply swiftui-pro review fixes` landed recently on this branch, and the prior `SWIFTUI_PRO_REVIEW.md` was just deleted. The findings below are the SwiftUI-specific items that surfaced from the three Explore agents and verification reads.

### 8.1 Oversized view files — see §9.2 for the split proposal
- **Location:** `OnboardingStoriesView.swift`, `GalleryView.swift`, `MeView.swift`, `CategoryDetailView.swift`
- **What:** Listed in detail under §9.2.
- **Why:** Both a structural and a perf concern; mirrors §7.3.
- **Action:** Per §9.2.
- **Severity:** High

### 8.2 Hardcoded animation durations scattered across files
- **Location:** `OnboardingStoriesView.swift` (~25 occurrences), `GalleryView.swift` (7), `SleepGoalArcPicker.swift` (5), `DayCanvasViewerView.swift` (4), `EnergyGradientBackground.swift` (4), and similar
- **What:** `.animation(.easeInOut(duration: 0.8), value: …)` and friends with magic numbers.
- **Why:** Tuning a global feel later requires touching every file. Some durations repeat (0.8 for transitions, 1.5 for emphasis).
- **Action:** Introduce a `Utilities/AnimationDurations.swift` with named constants for the common patterns (slideTransition, emphasize, dismiss). Leave one-off values inline.
- **Severity:** Low

### 8.3 Inconsistent date-helper usage in views
- **Location:** `StepsTrader/Views/DayCanvasViewerView.swift` (inline `endOfDay`), `StepsTrader/Utilities/DayBoundary.swift` (canonical), `StepsTrader/Extensions/Date+Today.swift`
- **What:** Multiple date helpers exist; `DayBoundary` is canonical, but view-local helpers persist.
- **Why:** Risk of date arithmetic divergence (one helper using `Calendar.current`, another using a configured `dayEndHour`).
- **Action:** Delete the local `endOfDay` from `DayCanvasViewerView`; route through `DayBoundary`.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright
- `StepsTrader/Services/ProfileLocationManager.swift` — 118 LOC, zero references in `StepsTrader/**` or `Steps4Tests/**`. CoreLocation + geocoding service from a removed feature. Severity: **High**.
- `test.txt` (root) — single line "hello", no apparent purpose. Severity: **Low**.
- `icon_gen_output.txt` (root) — icon-generation tool output. Severity: **Low**.

### 9.2 Oversized files (>500 LOC) — refactor candidates
Severity for the category overall: **High** (testability + change risk). Individual splits are sized roughly equally.

- **`StepsTrader/Views/OnboardingStoriesView.swift:1-1974`** — 31 `@State` vars, 10+ slide variants in one struct, 34 internal helpers. Propose: extract per-slide views (`ColdOpenSlide`, `CanvasSleepSlide`, …) into `Views/Onboarding/Slides/`; lift slide selection into a `OnboardingSlideRouter` value type; move analytics into a small `OnboardingAnalytics` helper.
- **`StepsTrader/Views/GalleryView.swift:1-1657`** — couples canvas loading, sync, toolbar state, moment-entry sheet, edit mode, and wide-canvas detection. Propose: `CanvasToolbarState` and `CanvasEditState` as `@Observable` value types; `CanvasLoaderManager` for remote bootstrap; sub-views `CanvasGridView`, `CanvasToolbarView`, `CanvasMomentPaywallView`.
- **`StepsTrader/Services/AuthenticationService.swift:1-1307`** — 41 methods, password reset + profile + session-monitor + sign-in all in one class. Propose: `AuthenticationService+PasswordReset`, `+Profile`, `+SessionManagement` extensions; consider extracting raw Supabase HTTP into a `SupabaseAuthClient` (would also enable easier unit tests with a mock client).
- **`StepsTrader/AppModel+DailyEnergy.swift:1-1146`** — split further into `AppModel+CustomActivities`, `AppModel+Moments`, `AppModel+CanvasSlots`. Also fold the 8 private file-scope keys into `SharedKeys` (§9.4).
- **`StepsTrader/Views/MeView.swift:1-1119`** — extract `RadarLayout` and `RadarBackgroundRenderer` as standalone types; move `pastDays` / `serverFetch` state into a `MeViewModel`.
- **`StepsTrader/Views/CategoryDetailView.swift:1-900`** — extract `ActivityGridView`, `UsageBreakdownView`, `UnlockSheetView`.
- **`StepsTrader/Views/Components/EnergyGradientBackground.swift:1-841`** — fine as one file for rendering consistency; just document render paths in a header comment.
- **`UnlockWidget/UnlockWidgetViews.swift:1-808`** — extract reusable `BudgetBar`, `AppGridItem`, `TicketGroupLabel` into `WidgetComponents/` for medium/large/compact reuse.
- **`UnlockWidget/UnlockTimelineProvider.swift:1-791`** — extract `WidgetBudgetCompute` value type; module-scope `static let` formatters.
- **`StepsTrader/Views/PaywallView.swift:696`** — moderate; extract feature list and CTA sections.
- **`StepsTrader/Views/Settings/SettingsAppearancePage.swift:655`** — extract gradient/palette picker, shape pickers, daily-random toggle.
- **`StepsTrader/StepsTraderApp.swift:621`** — extract handoff handling and PayGate-flag handling into separate types (mostly mechanical).
- **`StepsTrader/AppModel.swift:603`** — already extension-organized cleanly; no further split needed.
- **`StepsTrader/Stores/SubscriptionStore.swift:599`** — consider extracting `customerInfoStream` consumption into a `CustomerInfoObserver`.
- **`StepsTrader/Services/SupabaseSyncService.swift:594`** — already split into `+Stats`, `+Preferences`, `+Canvas`, `+Analytics`, `+TicketGroups`, `+Routines`, `+DeviceToken`. Leave as is.
- **`StepsTrader/Views/GenerativeCanvasView.swift:588`** — borderline; split if you touch it.
- **`StepsTrader/Views/MainTabView.swift:581`** — borderline; split tab-specific configuration if you touch it.
- **`StepsTrader/Views/SettingsSheet.swift:567`** — borderline.
- **`StepsTrader/Services/HealthKitService.swift:528`** — leave as one file; coherent.

### 9.3 `OnboardingPreview/Sources/OnboardingStoriesView.swift` is a symlink, not a duplicate
- **Locations:** `OnboardingPreview/Sources/OnboardingStoriesView.swift` → `../../StepsTrader/Views/OnboardingStoriesView.swift`
- **What:** Verified: the SPM target's file is a symbolic link to the canonical view. `diff` reports no differences.
- **Action:** None on the file itself. Add a one-paragraph comment in `OnboardingPreview/Package.swift` or repo `README.md` noting the symlink so future contributors don't try to "fix" it. Confirm CI / `xcodebuild` on macOS handles the symlink (it currently does).
- **Severity:** Low

### 9.4 Duplicated key constants in `AppModel+DailyEnergy.swift`
- **Locations:** `StepsTrader/AppModel+DailyEnergy.swift:5-13` (8 private file-scope `_…Key` constants) vs `StepsTrader/Utilities/SharedKeys.swift:25-26, 42-45, etc.` (same string values)
- **What:** Comment at line 5 says the file-scope versions exist to avoid `@MainActor` isolation on static lets. But `SharedKeys` is a non-isolated enum — using its constants directly does not require `await`.
- **Action:** Inline `SharedKeys.dailyEnergyAnchor` etc. at the call sites; delete the eight file-scope `let`s and the comment.
- **Severity:** Medium

### 9.5 Hardcoded URL with force-unwrap
- **Location:** `StepsTrader/Views/Settings/SettingsShortcutPage.swift:10`
- **What:** `private let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/…")!`
- **Why:** Static string is well-formed today, but a forced unwrap will trap if the literal is ever mistyped.
- **Action:** Move to `AppConstants.URLs` (alongside other URLs) as a non-optional constant, initialized via a `staticString`-based helper.
- **Severity:** Low

### 9.6 `fatalError()` in unavailable inits — intentional
- **Location:** `StepsTrader/Metal/MetalSmudgeRenderer.swift:144`, `StepsTrader/Metal/MetalShaderParkRenderer.swift:52`
- **What:** Both flagged by static-error grep, but both are marked `@available(*, unavailable) private override init()`, so they exist purely to block the no-arg init. The `fatalError()` is unreachable.
- **Action:** None — this is the documented pattern for static-factory-only types.
- **Severity:** Low

### 9.7 Unresolved TODOs / FIXMEs
- **Location:** ~33 TODO comments across `StepsTrader/`, `UnlockWidget/`, `DeviceActivityMonitor/`, `ShieldAction/`, `ShieldConfiguration/`, `Shared/`.
- **What:** 24 are sensoryFeedback migration (§4.1). The remainder are mostly forward-looking ("sync moment labels via moment_labels JSONB" at `Models/EphemeralMoment.swift:11`; minor cleanup notes).
- **Action:** Close the sensoryFeedback bulk; convert the rest into GitHub issues or leave with explicit ticket references so they don't bit-rot.
- **Severity:** Medium

### 9.8 Magic constants that should be named
- **Location:** Spread across UI; obvious offenders include JPEG quality literals in image encoders, opacity values (`0.6`, `0.85`) repeated across components, and animation timings (see §8.2).
- **Action:** Make a single pass through the largest files and extract constants where the value appears 3+ times. Don't over-extract — single-use literals should stay inline.
- **Severity:** Low

### 9.9 Five `print()` calls outside `#if DEBUG`
- **Location:** `OnboardingPreview/Sources/Stubs.swift` (1, intentional — preview-only), `StepsTrader/Views/OnboardingDemoView.swift` (4, demo-only view used in QA flows)
- **What:** Spot-verified the 3 `DeviceActivityMonitorExtension.swift` prints Agent B initially flagged — they ARE properly guarded by `#if DEBUG` (file lines 38-40, 45-47, 55-57). Drop that part of the agent's finding.
- **Action:** Wrap the 4 `OnboardingDemoView` prints in `#if DEBUG` or convert to `AppLogger.…debug(…)`. Leave `Stubs.swift` alone (SPM preview-only).
- **Severity:** Low

### 9.10 Markdown documentation at repo root
- **Location:** Root — `BRANDBOOK.md`, `MARKETING_COMPETITOR_RESEARCH.md`, `ARTICLE_BLOG.md`, `MANUALS_TEXTS.md`, `POSITIONING_ANGLES_SKILL.md`, `PROJECT_STRATEGY.md`, `TONE_OF_VOICE.md`, `ONBOARDING_FLOW.md`, `CanvasPalettes.md`, `CanvasLab-Spec.md`, `CanvasBodyMindHeart.md`, `PROJECT_HISTORY.md`, `LOG_REPORT.md`, `AUDIT_REPORT.md`, `Notes.md`, `CODE_AUDIT.md`, `CODE_AUDIT_PR_moment.md`
- **What:** 17 Markdown docs at root. About half are operational (architecture, history, this audit) and half are marketing/positioning content tangential to the codebase.
- **Action:** Move marketing-only docs (`BRANDBOOK.md`, `MARKETING_COMPETITOR_RESEARCH.md`, `ARTICLE_BLOG.md`, `POSITIONING_ANGLES_SKILL.md`, `TONE_OF_VOICE.md`, `MANUALS_TEXTS.md`) into `docs/marketing/`. Keep code/architecture docs at root.
- **Severity:** Low

### 9.11 Naming / organization observations
- **Location:** Repo-wide
- **What:** `Energy*` (model: `EnergyCategory`, `EnergyOption`, `EnergySignature`), `daily*` (qualifies temporal anchoring: `dailyEnergyAnchor`, `dailyCanvasSlots`), and `spent*` (balance deduction) form a coherent vocabulary once you know the rules. Not actually inconsistent, just under-documented.
- **Action:** Add a one-paragraph "Domain vocabulary" section to `README.md` or `CLAUDE.md` so the prefixes don't get treated as accidents.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

Patterns worth applying repo-wide rather than one finding at a time:

1. **Plan the Swift 6 strict-concurrency upgrade as a single focused PR.** Most of §3 is latent — `@unchecked Sendable` boxes, untracked `Task` handles, Combine sink → Task patterns, completion-handler callbacks of UN/UNUserNotificationCenter. None is urgent in Swift 5 mode, but they'll cascade when the language mode flips. Make one branch that turns on `SWIFT_STRICT_CONCURRENCY=complete`, fix until clean, then merge. Trying to address them piecemeal under Swift 5 is hard to verify (the compiler stays silent).
2. **Migrate `ObservableObject` + `@Published` → `@Observable` for stores and `AppModel`.** This unlocks finer-grained invalidation (mitigates the "any change re-renders everything" fan-out in §7.4), removes the Combine sink fan-out pattern that's a source of untracked Tasks (§3.5), and is a precondition for `@Bindable` + new-style binding-based UI elsewhere in the project.
3. **Centralize App-Group state behind a single actor in `Shared/`.** Multiple processes (main app, DeviceActivityMonitor, ShieldAction, UnlockWidget) read/write the same `UserDefaults(suiteName:)`. Right now each process does its own decode/encode/save dance, and compound writes are not synchronized (§5.2). A `Shared/AppGroupStore.swift` actor with typed accessors would (a) make the cross-process contract explicit, (b) be unit-testable, and (c) be the natural place to add `NSFileCoordinator`-based locking once that matters.
4. **Split `Secrets.xcconfig` per build configuration (§6.1).** With CI signing keys and staging databases this is table stakes; deferring it gets harder as the project accumulates production-only state.
5. **Bulk-migrate UIKit haptics → `.sensoryFeedback`.** 24 known sites (§4.1) in a single PR, sortable as the canonical example of "we have a planned migration; let's finish it instead of carrying TODOs."
6. **Add `[weak self]` + `Task.isCancelled` checks as a code-review pattern.** Several findings (§3.5, §3.6, §3.9, §3.10, §5.3) trace to the same anti-pattern: long-running awaits inside a Task that captures self without re-checking cancellation. A single short style note ("after every `await`, either re-check cancellation or document why it's safe not to") would prevent recurrences.
7. **Document the threading contract on cross-process helpers.** `ShieldRebuildHelper`, `SharedKeys`, the App-Group store, and anything in `Shared/` should carry a one-paragraph header comment about which processes call them and from which actor. Auditing this is hard without explicit annotations.

---

## 11. What was NOT audited

- `admin-panel/` (Next.js + Supabase admin dashboard) — out of scope.
- `tg-admin/` (Cloudflare Worker Telegram bot) — out of scope.
- `web/` and the standalone marketing site — out of scope.
- Build settings and Xcode project structure beyond shared schemes and the four `*.xcconfig` files.
- Third-party dependency internals — `RevenueCat 5.72.0` (SPM) and the Supabase JS used in the Edge Function are treated as black boxes.
- `Steps4Tests/` and `Steps4UITests/` — light scan only. No deep coverage review. `SubscriptionGateTests.swift` was opened and confirmed to be a meaningful unit-test file.
- Algorithmic correctness of Metal kernels (`MetalSmudgeRenderer`, `MetalShaderParkRenderer`, and the three `.metal` source files in `StepsTrader/Metal/`) — surface checks only.
- Entitlements XML files — see §6.7.
- StoreKit configuration — `.storekit` file structure not opened; not a substitute for verifying products match App Store Connect.
- Localization correctness — `Localizable.xcstrings` exists but wording / completeness was not assessed.
- Instruments profiling — performance findings are *potential* hot paths; none was verified by a trace. See §7.3 / §7.2 notes.
- A separate SwiftUI-expert pass was not re-run. Recent commit `c5377a5 refactor: apply swiftui-pro review fixes` and the deletion of `SWIFTUI_PRO_REVIEW.md` indicate that work was done; SwiftUI findings here come from the three Explore agents only.
- The Shield extension targets (`ShieldAction`, `ShieldConfiguration`) got light coverage — entry points were skimmed but not deeply read. Their entitlements files were not opened.
- `supabase/migrations/` SQL was not audited beyond the Edge Function in §6.3.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line. Each High finding has an exact line range, not "scattered throughout."

This audit produced no Critical findings; what follows verifies the High-severity items and a few notable demotions.

### High findings — verified file:line

- **§3.2** — `StepsTrader/Services/HealthKitService.swift:29-32`. Confirmed `private final class UnsafeSendableBox: @unchecked Sendable` with a mutable `var value: Bool`. Used at `:108-128` as the timeout box.
- **§3.3** — `StepsTrader/NotificationManager.swift:35-42, 57-64, 79-86, 112-119`. Confirmed all uses of `UNUserNotificationCenter.current().add(request) { error in … }` and the file's `requestPermission()` already using the async overload for inconsistency.
- **§4.1** — Repo-wide grep `grep -rn "TODO.*sensoryFeedback"` returns 24 matches across the listed files. Picked five at random and confirmed.
- **§5.1** — `StepsTrader/AppModel+PayGate.swift:101-110`. Confirmed: refund branch clears the four budget keys, calls `refund(cost:)`, returns. No `payGateError` is set, no `dismissPayGate` is called, no toast.
- **§5.2** — `StepsTrader/Stores/BlockingStore.swift:87-93` (writes `appSelection` via `defaults.set(data, forKey: SharedKeys.appSelection)`) and `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift:172-192, 263-294` (reads `appSelection`, decodes, mutates per-app keys). No `NSFileCoordinator`, no lock.
- **§5.3** — `StepsTrader/Services/HealthKitService.swift:396-409`. Confirmed Task is not stored anywhere; `stopObservingSteps()` at `:412-420` cannot reach it.
- **§6.1** — `Config/Debug.xcconfig:4` and `Config/Release.xcconfig:4` both `#include "Secrets.xcconfig"`. No conditional environment split exists.
- **§9.1** — `StepsTrader/Services/ProfileLocationManager.swift:6, 105`. Grep for `ProfileLocationManager` returns only those two self-references; no other file in `StepsTrader/`, `Steps4Tests/`, or `OnboardingPreview/` imports it.
- **§9.2** — File sizes confirmed via `wc -l`: OnboardingStoriesView 1974, GalleryView 1657, MeView 1119, CategoryDetailView 900.

### Demotions from agent-flagged Critical (transparency for the user)

- **`handleAuthorization` missing `@MainActor`** (Agent A, Critical). **Demoted to no-finding.** `AuthenticationService` is declared `@MainActor class` at `:62-63`; the method inherits isolation. The inner `Task { @MainActor in … }` at `:347` is redundant but not unsafe.
- **`Timer.scheduledTimer` closure not on MainActor** (Agent A, Critical) at `AppModel.swift:344-355`. **Demoted to Low.** The closure body is `Task { @MainActor [weak self] in … }` — the MainActor hop is already there. The remaining issue (recursive reschedule silently ending on `self == nil`) is captured at §3.12 and §5.10 at appropriate severity.
- **HKObserverQuery completion handler "executes concurrently with MainActor mutations"** (Agent A, Critical) at `HealthKitService.swift:446`. **Demoted to Medium (§3.6).** Handler `[weak self]`-guards, dispatches into a `Task`, and `await MainActor.run`s the UI callback. Still has a lifetime bug (cited at §3.6) but isn't a data race.
- **HKSampleQuery `continuation.resume` from background "violates actor isolation"** (Agent A, Critical) at `HealthKitService.swift:162-207`. **Dropped.** Continuations are designed to bridge any-thread resume to the awaiting actor; this is idiomatic Swift.
- **DeviceActivityMonitor calls `ShieldRebuildHelper.rebuild()` from background** (Agent A, Critical) at `DeviceActivityMonitorExtension.swift:158-306`. **Demoted to Medium (§3.8).** This is the documented DeviceActivityMonitor pattern and `ManagedSettingsStore` is safe to call from extension callbacks today. Listed as a Swift 6 concern, not a present bug.
- **Release builds ship with dev Supabase URL** (Agent C, Critical) at `Steps4/Info.plist:21-24`. **Demoted to High (§6.1).** Both configs use the same `Secrets.xcconfig` — the bug is "no env split exists," not "release ships dev URL."
- **Handoff token forgery** (Agent C, High) at `StepsTrader/Models/HandoffToken.swift`. **Demoted to Low (§6.4).** Local-only token, same-device same-user trust boundary.
- **`print()` calls not behind `#if DEBUG` in DeviceActivityMonitor** (Agent B, Low). **Dropped.** Verified at `DeviceActivityMonitorExtension.swift:38-40, 45-47, 55-57` — they're properly wrapped.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.
