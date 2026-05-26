# Steps4 PR Code Audit — `feature/moment-ephemeral-activity`

Generated 2026-05-25. Scope: the diff between `main` and `HEAD` on branch `feature/moment-ephemeral-activity` (183 files, +6275 / −2261). Findings are restricted to lines this PR added or modified; pre-existing code on untouched lines is out of scope.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

Three parallel Explore agents covered concurrency/API modernity, dead code/duplication, and bugs/security/performance. Critical and High findings were spot-verified by opening the cited lines before being propagated here.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[Critical / Security] `send-push` Edge Function accepts any non-empty `Authorization` header and broadcasts to all iOS tokens** — §6.1 — `supabase/functions/send-push/index.ts:108-134`. Any caller with a token-shaped string can trigger a full-fleet push.
2. **[High] `deleteAccount` does not log out RevenueCat** — §5.1 — `StepsTrader/Services/AuthenticationService.swift:184-219`. Subscription state leaks across accounts on the same device.
3. **[High] Push token never removed on `signOut` / `deleteAccount`** — §5.2 — `StepsTrader/Services/SupabaseSyncService+DeviceToken.swift:43-66` (handler exists but is never called). Push notifications meant for the new user can still hit the previous account's device.
4. **[High] Anonymous sign-in fails silently on HTTP ≥ 400** — §5.3 — `StepsTrader/Services/AuthenticationService.swift:160-164`. The user sees a blank/partial UI with no error surfaced.
5. **[High] Post-login `Task` is fire-and-forget, not cancellable on sign-out** — §3.1 — `StepsTrader/Services/AuthenticationService.swift:313-321`. A late-arriving sync can write to an `AppModel` whose user has changed.
6. **[High] `MomentEntrySheet.commit` ignores the `addMoment` Optional return** — §5.4 — `StepsTrader/Views/MomentEntrySheet.swift:219-224`. The sheet dismisses even when the moment was rejected by `AppModel`.
7. **[High] Moment labels are local-only — TODO acknowledges no server sync** — §5.5 — `StepsTrader/Models/EphemeralMoment.swift:11`. App reinstall or second device loses the human-readable label while keeping the `moment_<uuid>` reference.
8. **[High] APNs registration callback hops actors without explicit isolation** — §3.2 — `StepsTrader/StepsTraderApp.swift:9-15` + `StepsTrader/Services/SupabaseSyncService+DeviceToken.swift:6-41`. The async sync runs on whichever actor the system delegate fires from.
9. **[High] Force-unwrap on `image.cgImage` in `ShapeIconCache`** — §5.6 — `StepsTrader/Services/ShapeIconCache.swift:63`. Zero-sized rect or renderer failure would crash a hot UI path.
10. **[Medium] Two new top-level Markdown notes are committed to `main`** — §9.1 — `SWIFTUI_PRO_REVIEW.md` (370 LOC) and `CircleShapeRendering.md` (285 LOC) look like review artefacts rather than canonical docs.

---

## 2. Quick wins (≤30 min each)

These deliver outsized value relative to effort and have no architectural ripples.

- **Move or delete root-level Markdown notes** — `SWIFTUI_PRO_REVIEW.md`, `CircleShapeRendering.md`. Move to `docs/` or drop from the commit.
- **Confirm `skills-lock.json` belongs in the repo** — repo-root tooling artefact at `skills-lock.json`; either keep with a one-line README mention or add to `.gitignore`.
- **Hook `removeDeviceToken` into `signOut` / `deleteAccount`** — handler already implemented at `StepsTrader/Services/SupabaseSyncService+DeviceToken.swift:43-66`; one `await` per call site fixes §5.2.
- **Add `await SubscriptionStore.shared.logOut()` to `deleteAccount`** — mirror the call already in `signOut` at `StepsTrader/Services/AuthenticationService.swift:140`.
- **Replace `image.cgImage!` with a `guard let` fallback** — `StepsTrader/Services/ShapeIconCache.swift:63`. Return a 1×1 transparent image on failure rather than crashing.
- **Surface the anonymous-signup error to `self.error`** — `StepsTrader/Services/AuthenticationService.swift:160-164`. Even a generic localized "Couldn't initialise account" beats silent failure.
- **Name the 3 s warning timer** — `StepsTrader/Views/MomentEntrySheet.swift:209`. Replace literal `.seconds(3)` with a named constant on the struct.
- **Wrap the post-login `Task` capture with `[weak self]` and store the handle** — `StepsTrader/Services/AuthenticationService.swift:313-321`. Cancel from `signOut`.
- **Remove unused `AnyTransition.motionSafe()`** — `StepsTrader/Utilities/ReduceMotion.swift:49-50`.

---

## 3. Concurrency

### 3.1 Post-login `Task` is unstructured and uncancellable
- **Location:** `StepsTrader/Services/AuthenticationService.swift:313-321`
- **What:** After Apple sign-in succeeds, `Task { await SubscriptionStore.shared.logIn(...); await SupabaseSyncService.shared.performFullSync(model: appModel) }` is spawned without storing the handle or using `[weak self, weak appModel]`.
- **Why:** If the user signs out (or the auth-service / model is deallocated) before the full sync completes, the task keeps both alive past their intended lifetime and may write back into a stale `AppModel`. `signOut` (line 132) cannot cancel it.
- **Action:** Store the task in a `private var postLoginSyncTask: Task<Void, Never>?` and cancel it in `signOut`/`deleteAccount`. Use `[weak self, weak appModel]` and guard both before continuing.
- **Severity:** High

### 3.2 APNs registration crosses actor boundaries implicitly
- **Location:** `StepsTrader/StepsTraderApp.swift:9-15` and `StepsTrader/Services/SupabaseSyncService+DeviceToken.swift:6-41`
- **What:** `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` is invoked by UIKit with no actor context; it spawns `Task { await SupabaseSyncService.shared.registerDeviceToken(hex) }`. `SupabaseSyncService` (and its `+DeviceToken` extension) is not annotated `@MainActor` or `actor`.
- **Why:** The function therefore runs on the global executor. While the work it does is purely network I/O, sharing `network` and Supabase state across non-isolated callers is fragile and will emit Swift 6 / strict-concurrency warnings once enabled.
- **Action:** Either mark `SupabaseSyncService` `@MainActor` (matches the rest of the service layer), make it an `actor`, or annotate the two new methods `nonisolated` and document the contract. Either way, capture the call from the delegate in `await MainActor.run { … }` if you want UI-thread invariants.
- **Severity:** High

### 3.3 `MomentEntrySheet.scheduleWarningDismiss` leaks the warning task on rapid re-entry
- **Location:** `StepsTrader/Views/MomentEntrySheet.swift:206-215`
- **What:** Each call cancels the previous `warningDismissTask` and stores a new one, but if the user spam-taps several full categories, the cancelled task continuations still hold the closure (with `withAnimation`) until they observe the cancel after the 3 s sleep.
- **Why:** Low-impact, but it does pin the `View` reference longer than necessary; if the sheet is dismissed mid-countdown, `onDisappear` cancels the latest task but earlier cancelled ones still consume runtime until their sleep wakes.
- **Action:** Add `guard !Task.isCancelled else { return }` *before* `withAnimation` (already present after sleep — also useful before scheduling new state on a cancelled task), and consider one shared `@State` flag flipped via a `Task.sleep` rather than allocating a new task per tap.
- **Severity:** Low

### 3.4 `EphemeralMoment` is implicitly `Sendable` but not declared
- **Location:** `StepsTrader/Models/EphemeralMoment.swift:13-38`
- **What:** Struct with value-type fields, marked `Codable` + `Equatable`, but no explicit `Sendable` conformance. It is stored on `@MainActor AppModel.dailyMoments` and shipped into `SupabaseSyncService` (non-isolated) for sync.
- **Why:** Today the auto-`Sendable` inference is fine; under Swift 6 / strict-concurrency the implicit conformance will only hold while *all* fields stay Sendable, and the compiler will not emit a diagnostic if a future maintainer adds a non-Sendable field.
- **Action:** Add explicit `: Sendable` to the declaration. Same call applies to any other new value type that crosses the sync boundary in this PR.
- **Severity:** Low

### 3.5 `applyCachedSessionState` is callable from any context but mutates `@Published`
- **Location:** `StepsTrader/Services/AuthenticationService+CachedProfile.swift:40-48`
- **What:** Extension methods are inherited as `@MainActor` because `AuthenticationService` is `@MainActor`, so this is fine at runtime — but the call sites at `StepsTrader/Services/AuthenticationService.swift:588-592` and `620-624` rely on that implicit isolation. The inner `applyCachedSessionState` at line 620 sits inside a `do/catch` where the indentation is misaligned (it nests under the outer scope, not the catch branch), which obscures the actor-hop chain.
- **Why:** Functional today; but the indentation makes the second call easy to misread as catch-scoped.
- **Action:** Re-indent the second call so it visibly belongs to the `if currentUser == nil` branch, and add a one-line comment that both paths are `@MainActor`.
- **Severity:** Low

### 3.6 `HealthKitService.fetchSamples` watchdog can outlive the continuation
- **Location:** `StepsTrader/Services/HealthKitService.swift:108-134`
- **What:** A `withCheckedThrowingContinuation` is paired with a detached watchdog `Task` that sleeps then calls `cont.resume`. The continuation has a sendable-box guard for double-resume, but the watchdog task itself is never cancelled when the HK callback fires, so it sleeps to completion every time.
- **Why:** Minor — the guard prevents the trap. But every call leaks one short-lived sleeping task per fetch.
- **Action:** Store the watchdog `Task<Void, Never>?` outside the continuation closure and `cancel()` it from the HK completion handler, or use `withTaskCancellationHandler` and a timed cancellation pattern.
- **Severity:** Medium

### 3.7 `try? await Task.sleep(...)` without `Task.isCancelled` follow-up
- **Locations:** `StepsTrader/Views/MomentEntrySheet.swift:209`, `StepsTrader/AppModel.swift:422`, `StepsTrader/StepsTraderApp.swift:162, 168, 173`, `StepsTrader/Services/HealthKitService.swift:132`
- **What:** All five new sites swallow cancellation silently and then continue to mutate state.
- **Why:** When a cancellation arrives mid-sleep, the code resumes and performs work the caller already disowned (animation flips, paywall presentation, state mutation).
- **Action:** Follow each `try? await Task.sleep(…)` with `guard !Task.isCancelled else { return }`. The Moment entry sheet already does this at line 210 — apply the pattern uniformly.
- **Severity:** Low

---

## 4. API modernity

### 4.1 `AuthenticationService` uses `ObservableObject` + `@Published` rather than `@Observable`
- **Location:** `StepsTrader/Services/AuthenticationService.swift:62-75`
- **What:** Class is declared `@MainActor class AuthenticationService: NSObject, ObservableObject` with five `@Published` properties. Deployment targets in this workspace go from 17 up to 26.1; `@Observable` is available across all of them.
- **Why:** `@Observable` gives finer-grained SwiftUI re-render tracking and removes the need for `ObservedObject` wrappers at call sites. Mixing both styles in the codebase is the bigger pain than either alone.
- **Action:** Migrate to `@Observable` when this file next sees structural work. Not urgent because the existing API contract is wide.
- **Severity:** Medium

### 4.2 `MomentEntrySheet` adopts modern SwiftUI APIs correctly
- **Location:** `StepsTrader/Views/MomentEntrySheet.swift:140-144`
- **What:** Uses `.presentationDetents([.medium])`, `.presentationDragIndicator(.hidden)`, `.choicesSheetPresentationBackground()`, `.presentationCornerRadius(28)`, `.sensoryFeedback(.warning, trigger:)`. All correct iOS 17+ patterns.
- **Why:** Worth noting as a positive — this is the template other sheets in the repo should follow.
- **Action:** None. Use this as the canonical example when refactoring other sheets.
- **Severity:** N/A

### 4.3 Direct `JSONEncoder()` / `JSONDecoder()` instantiations in new code
- **Locations:** `StepsTrader/Services/AuthenticationService+CachedProfile.swift:18, 28`, `StepsTrader/Services/AnnouncementService.swift` (decoder), `StepsTrader/Services/SupabaseSyncService+DeviceToken.swift:30` (uses `JSONSerialization` instead).
- **What:** New call sites instantiate fresh encoders/decoders rather than going through `supabaseEncoder` / `supabaseDecoder` (defined at `AuthenticationService.swift:634-644` with ISO8601 date strategy).
- **Why:** Inconsistent date handling — anywhere a `Date` field eventually appears in the cached `AppUser` JSON, the format will differ from server payloads.
- **Action:** Expose the configured encoders as static accessors (`SupabaseCodec.encoder` / `.decoder`) and use them from all Supabase-adjacent code.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 `deleteAccount` does not call `SubscriptionStore.shared.logOut()`
- **Location:** `StepsTrader/Services/AuthenticationService.swift:184-219`
- **What:** `deleteAccount` clears the keychain session, cached profile, avatar, Apple display name, and custom-nickname flag — but `signOut` at line 132-141 *also* calls `Task { await SubscriptionStore.shared.logOut() }`, and `deleteAccount` does not.
- **Why:** RevenueCat keeps the deleted user's identity attached on the device. If a different Apple ID signs in afterwards, the previous entitlement state can leak into the new account.
- **Action:** Mirror `signOut`'s RC logout call in `deleteAccount` *before* clearing the local session.
- **Severity:** High

### 5.2 Push token is never removed on logout or account deletion
- **Location:** `StepsTrader/Services/SupabaseSyncService+DeviceToken.swift:43-66` (handler exists) vs `StepsTrader/Services/AuthenticationService.swift:132-141, 184-219` (callers don't invoke it)
- **What:** `removeDeviceToken(_:)` is fully implemented but is not referenced anywhere in the app. `signOut` and `deleteAccount` leave the `device_tokens` row in place with the now-stale `user_id`.
- **Why:** A new sign-in on the same device upserts the same token under a new `user_id` (unique index is on `token` alone — see `supabase/migrations/20260521_device_tokens.sql:12`), so the *next* push will hit the right user. But until that happens, the `send-push` function will deliver the previous account's notifications to the device.
- **Action:** Call `await SupabaseSyncService.shared.removeDeviceToken(currentToken)` from `signOut` and `deleteAccount`. Cache the current token in `NotificationManager` (or read it back from `AppDelegate`) so the call has a value to pass.
- **Severity:** High

### 5.3 `signInAnonymously` swallows HTTP errors without surfacing them
- **Location:** `StepsTrader/Services/AuthenticationService.swift:145-180` (specifically the `guard http.statusCode < 400` branch at 160-164)
- **What:** When the server returns ≥ 400, the function logs and returns. The caller (`loadStoredSessionAndRefreshUser` at line 578) ignores the return value, so `isAuthenticated` stays false and `error` stays nil.
- **Why:** A misconfigured anon key or a Supabase outage on cold launch produces a silent dead app — the UI thinks "still loading" but never recovers.
- **Action:** Either set `self.error` to a localized "Couldn't reach Steps. Try again." or make `signInAnonymously` throw so the caller can decide. Add a retry with backoff for transient failures.
- **Severity:** High

### 5.4 `MomentEntrySheet.commit` discards the `addMoment` Optional return
- **Location:** `StepsTrader/Views/MomentEntrySheet.swift:219-224` and `StepsTrader/AppModel+DailyEnergy.swift:746-768`
- **What:** `addMoment(...)` returns `EphemeralMoment?` — `nil` when label is empty or category is full. `commit` runs its own guard, then calls `addMoment` and immediately calls `dismiss()` regardless of the return value.
- **Why:** The category-full check on `commit`'s side and `addMoment`'s side both read `dailySelectionsCount`. The two reads aren't atomic; a `nil` return is possible if state changes between them (e.g., a background sync writes new selections in between). The sheet dismisses, no toast, no animation, and the user thinks the moment was saved.
- **Action:** Capture the return value, and on `nil` show the existing "category full" warning area + re-enable the button instead of dismissing. Don't call `dismiss()` until you've confirmed success.
- **Severity:** High

### 5.5 Moment labels are local-only — no server sync
- **Location:** `StepsTrader/Models/EphemeralMoment.swift:11`
- **What:** Inline comment: "The human-readable label is local-only for now. TODO: sync moment labels via moment_labels JSONB column." Only the synthetic `moment_<uuid>` identifier syncs through the existing selection arrays.
- **Why:** Reinstalling the app, restoring from backup, or viewing history on a second device shows the moment as a generic `moment_<uuid>` token with no label or icon — effectively data loss for the user.
- **Action:** Either ship the JSONB column before this PR merges, or document the limitation in the release notes and the in-sheet copy ("only stays on this device"). The current "stays on today's canvas and history" subtitle at line 63 *implies* persistence, which is misleading.
- **Severity:** High

### 5.6 Force-unwrap on `image.cgImage` in `ShapeIconCache.render`
- **Location:** `StepsTrader/Services/ShapeIconCache.swift:63`
- **What:** `return UIImage(cgImage: image.cgImage!, scale: scale, orientation: .up)`. `UIGraphicsImageRenderer` returns a UIImage whose `cgImage` is non-nil for well-formed contexts, but a zero-`pixelSize` (e.g., from a future caller passing `size: 0`) or an interrupted render can return a UIImage with no backing CGImage.
- **Why:** This is a hot path called every time a shape icon needs to be rendered for the canvas/preview/picker. A nil unwrap crashes the app.
- **Action:** `guard let cg = image.cgImage else { return image }` (the renderer-produced `UIImage` is a valid fallback; the wrap to `cgImage` is only to change `scale`/`orientation`).
- **Severity:** Medium

### 5.7 Optimistic `isAuthenticated = true` survives non-invalidating refresh failures
- **Location:** `StepsTrader/Services/AuthenticationService.swift:610-628` and `+CachedProfile.swift:40-48`
- **What:** On cold start with a stored session, the code sets `isAuthenticated = true` from the cached profile, then attempts to refresh the token. If the refresh fails with a *transient* error (offline, 5xx), the catch branch keeps `isAuthenticated = true` and re-applies cached state. Only `isSessionInvalidatingError` errors flip it back.
- **Why:** Correct in the offline case, but the result is that a stale refresh token (one the *server* has invalidated but for which the client got a 503 from a different layer) can keep the user "logged in" until the next 401 from any other endpoint.
- **Action:** Track `isProfileFresh` separately, or after N consecutive refresh failures fall back to the anonymous-sign-in path. Document the contract: "we keep optimistic UI until any 401 from `/rest/v1/*`."
- **Severity:** Medium

### 5.8 `fetchResistanceUsers` relies on PostgREST `neq.` with empty value
- **Location:** `StepsTrader/Services/AuthenticationService.swift:953-957`
- **What:** Filter `URLQueryItem(name: "nickname", value: "neq.")` is intended to mean `WHERE nickname <> ''`. PostgREST does interpret this correctly today.
- **Why:** Correct behaviour today, but the syntax is non-obvious and any maintainer who URL-encodes the value will silently break it.
- **Action:** Add an inline comment documenting the operator, or switch to `nickname=not.is.null&nickname=neq.""` for explicitness.
- **Severity:** Low

### 5.9 `RadialHoldMenu` binding rewrite mixes direct mutation with `@Binding`
- **Location:** `StepsTrader/Views/RadialHoldMenu.swift` (the `feature/moment-ephemeral-activity` history — commits `3bb57de`, `8e74849`, `17d5fdf` rework `isFanOpen` between `Bool?` and `@Binding<Bool>`)
- **What:** The 4-commit dance suggests the binding contract is still being settled. Verify (a) the binding is single-source-of-truth and child no longer holds parallel `@State`, (b) `onDisappear` of the sheet cleanly tears down the open fan, (c) the share-button "remove from hierarchy" fix at commit `17d5fdf` doesn't leave a layout hole when the moment node is hidden.
- **Why:** Binding lifecycle issues are notorious for "works in dev, broken on cold app launch" regressions.
- **Action:** Add a UI test that opens the fan, dismisses, re-opens, and asserts no stale state. Spot-verify by toggling the fan rapidly while presenting the sheet.
- **Severity:** Medium

---

## 6. Security

### 6.1 `send-push` Edge Function does not verify the Authorization header
- **Location:** `supabase/functions/send-push/index.ts:108-134` (and the bundle-ID fallback at line 150)
- **What:** The function checks `if (!authHeader) { 401 }` and immediately proceeds. It never validates the JWT, never checks the role, never restricts the caller to service-role. Then it creates a service-role client (line 126-129), reads **all** rows from `device_tokens` where `platform = 'ios'` (no user-id filter), and pushes the supplied `title` + `body` to every device.
- **Why:** Any authenticated user (and trivially anyone who sends `Authorization: x`) can broadcast a push to the entire iOS install base. CORS is open (`Access-Control-Allow-Origin: *` at line 101), so this is reachable from a browser. This is a fleet-wide spam / abuse vector and a brand-impersonation risk.
- **Action:** Either (a) require service-role via `req.headers.get('Authorization')?.includes(SERVICE_ROLE_KEY)` plus constant-time compare, or (b) call `supabase.auth.getUser(authHeader.replace('Bearer ', ''))` and limit recipients to admins (an `admins` table or a custom JWT claim). Add per-IP rate limiting at the Edge layer. Tighten CORS to your own origins.
- **Severity:** Critical

### 6.2 `send-push` error response echoes APNs `reason` strings
- **Location:** `supabase/functions/send-push/index.ts:90-94, 188-196`
- **What:** Per-token results include `reason: errBody.reason` from APNs, and the final aggregated response includes counts. The reason strings (`BadDeviceToken`, `Unregistered`, …) are not sensitive on their own, but `String(e)` on a network failure (line 93) can include URL fragments that contain a fragment of the token.
- **Why:** Low-impact today because no tokens appear in `errBody.reason`. But if the function is ever called by an unauthenticated client (see §6.1) the response shape itself becomes a token-validity oracle.
- **Action:** Once §6.1 is fixed, this is acceptable. Otherwise, strip raw exception strings from the response and return a generic `"upstream_error"` to non-service callers.
- **Severity:** Low

### 6.3 `send-push` hardcoded bundle-ID fallback
- **Location:** `supabase/functions/send-push/index.ts:150`
- **What:** `Deno.env.get("APNS_BUNDLE_ID") ?? "personal-project.StepsTrader"` — defaults to a hardcoded ID if the env var is missing.
- **Why:** A misconfigured staging deploy will silently push under the production bundle ID, which APNs will reject with `DeviceTokenNotForTopic` — which §6.4 (below) then takes as a signal to *delete* the tokens. That deletion is permanent.
- **Action:** Make `APNS_BUNDLE_ID` required (throw on startup if missing). Or scope the cleanup at §6.4 to only delete on `BadDeviceToken` / `Unregistered`, not on `DeviceTokenNotForTopic` (a config error, not an invalid token).
- **Severity:** Medium

### 6.4 Invalid-token cleanup deletes on `DeviceTokenNotForTopic`
- **Location:** `supabase/functions/send-push/index.ts:167-183`
- **What:** Tokens whose response includes `DeviceTokenNotForTopic` are deleted from `device_tokens`. `DeviceTokenNotForTopic` means "this token isn't registered for *this* bundle" — usually a server config error, not a dead token.
- **Why:** Combined with §6.3, a wrong `APNS_BUNDLE_ID` env var would wipe the entire iOS device-tokens table on the first send.
- **Action:** Restrict deletion to `BadDeviceToken` and `Unregistered`. Log `DeviceTokenNotForTopic` separately as an operator alert.
- **Severity:** High

### 6.5 No rate-limit on anonymous user creation
- **Location:** `StepsTrader/Services/AuthenticationService.swift:145-180` and `supabase/migrations/20260523_anonymous_auth.sql`
- **What:** Anonymous sign-up posts `{}` with the anon key as bearer; nothing in the migration adds a per-IP rate limit, and the `handle_new_user` trigger creates a `public.users` row on every successful signup.
- **Why:** A scripted attacker can fill `public.users` with millions of anonymous rows. Supabase Auth's built-in rate limits help, but rely on Captcha being enabled. Worth confirming with the dashboard settings.
- **Action:** Enable Captcha for the anonymous signup endpoint in the Supabase dashboard. Add a server-side `created_at` clean-up job for anonymous users that never converted within N days.
- **Severity:** Medium

### 6.6 `device_tokens` unique constraint is on `token` alone
- **Location:** `supabase/migrations/20260521_device_tokens.sql:11-12`
- **What:** Unique index on `(token)`. APNs tokens are device-global, so this is semantically correct — but the table also has no foreign-key on `token` to a stable identifier; a `merge-duplicates` upsert from a new user just overwrites `user_id`.
- **Why:** This is *probably* what you want (silent take-over to the new user), but combined with §5.2 (no explicit delete on logout) the previous user's send-push targeting them by `user_id` will silently start hitting the new user.
- **Action:** Document the intended semantics in the migration. Pair §5.2's logout-delete with a server-side audit on `updated_at` so abandoned tokens age out after, say, 90 days.
- **Severity:** Low

### 6.7 `app_announcements` table is readable without auth
- **Location:** `supabase/migrations/20260522_app_announcements.sql:13-16`
- **What:** Policy "Anyone can read active announcements" with `USING (is_active = true)` and RLS on. Open to `anon` role.
- **Why:** Intentional per the migration comment ("visible to all users (including anonymous)") and consistent with the anonymous-auth flow.
- **Action:** No action. Documenting it here so a future security pass doesn't flag it.
- **Severity:** N/A

### 6.8 Cached profile JSON on disk
- **Location:** `StepsTrader/Services/AuthenticationService+CachedProfile.swift:13-22`
- **What:** Writes the `AppUser` (id, email, nickname, country, displayName, hasSetCustomNickname) as JSON in the Documents directory. Avatar bytes are stripped, so the file is small.
- **Why:** Documents is iCloud-backed by default. Email + nickname leaving the device with a generic iCloud restore is acceptable for this app's threat model, but worth surfacing — Supabase auth tokens live in the Keychain, but this profile JSON does not.
- **Action:** Consider setting `URLResourceValues.isExcludedFromBackup = true` on the cached-profile file, or move it to Application Support. Low priority.
- **Severity:** Low

### 6.9 No secret/token leakage in PR logs
- **Location:** swept across the diff
- **What:** All `AppLogger.auth.debug` / `.error` calls truncate user IDs to `prefix(8)`, never log access/refresh tokens, never log device tokens. The push-token registration logs only the status code.
- **Why:** Worth recording as a positive.
- **Action:** None. Pattern to preserve.
- **Severity:** N/A

---

## 7. Performance

### 7.1 `ShapeIconCache` is an unbounded in-memory dictionary
- **Location:** `StepsTrader/Services/ShapeIconCache.swift:10`
- **What:** `private var cache: [CacheKey: UIImage] = [:]` — no `NSCache`, no eviction, no purge on memory warning. Keys vary by `(shape, size, scale)`; the project supports multiple sizes and Retina scales, so a few dozen distinct entries are likely but bounded.
- **Why:** Unbounded is bad practice; the per-icon footprint is small (≤ 68×68@3x = ~50 kB), so the worst-case is on the order of a megabyte rather than catastrophic. But the singleton lives for the app's lifetime.
- **Action:** Switch to `NSCache<NSValue, UIImage>` (NSValue around the hashable key) or implement a manual LRU with a cap of, say, 32 entries. Add an `onMemoryWarning` observer that drops the cache.
- **Severity:** Medium

### 7.2 `OrganicBlobShapeRenderer` duplicates positioning math from `BlobShapeRenderer`
- **Location:** `StepsTrader/Shapes/OrganicBlobShapeRenderer.swift` vs `StepsTrader/Shapes/BlobShapeRenderer.swift`
- **What:** Both define `center()` / `frozenCenter()` / `radius()` with similar implementations but different scale constants and slightly different wobble/breathe frequencies. The duplication means each frame, both versions compute their own values, and any tuning has to be applied twice.
- **Why:** Performance impact is marginal but the maintenance cost is real. The per-frame allocations in both renderers (creating a new `Path` each tick) is the bigger concern; this renderer joins a known hot loop.
- **Action:** Extract a `ShapeKinematics` protocol or struct holding center/radius/animation params; let each renderer parameterise it. Profile the new renderer with Instruments for `CGPath` allocations on canvas redraw.
- **Severity:** Medium

### 7.3 `MomentEntrySheet` recomputes selection counts per render
- **Location:** `StepsTrader/Views/MomentEntrySheet.swift:25-46`
- **What:** `selectionsCount(for:)`, `isFull(_:)`, `firstAvailableCategory`, `allCategoriesFull` are computed on every body re-evaluation. The underlying `model.dailySelectionsCount(for:)` is O(1) (array `count` lookup).
- **Why:** No actual problem today. Flagged so future maintainers don't accidentally swap in an O(n) lookup.
- **Action:** Add a comment to `dailySelectionsCount` documenting it must remain O(1). No change needed otherwise.
- **Severity:** Low

### 7.4 `AnnouncementService.fetch` runs at app launch
- **Location:** `StepsTrader/Services/AnnouncementService.swift` (fetch) and call site in `StepsTrader/StepsTraderApp.swift`
- **What:** The service is constructed at app start and `fetchActiveAnnouncement()` is called early. The fetch awaits a Supabase REST call before populating `@Published activeAnnouncement`.
- **Why:** Not blocking initial UI render (it's a Task), but if the announcement banner is a noisy element on first launch it can flash in mid-onboarding.
- **Action:** Defer the announcement fetch until after `OnboardingCoordinator` reports complete. Or suppress the banner during onboarding flows.
- **Severity:** Low

### 7.5 Anonymous sign-in plus full sync on cold launch
- **Location:** `StepsTrader/Services/AuthenticationService.swift:574-629` and the post-login `Task` at 313-321
- **What:** Cold launch without a stored session: anonymous sign-up + profile fetch + RC `logIn` + `performFullSync`. All async, but several serial network round-trips before the user can see meaningful UI.
- **Why:** First-launch TTI may be noticeably long on flaky networks. Optimistic cached-state pattern is already in place for *return* users; first-launch users get no such shortcut.
- **Action:** Cache the anonymous user ID and skip the signup call on subsequent launches that didn't get it. Parallelise RC `logIn` and `performFullSync` rather than chaining them.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 `MomentEntrySheet` — modern hygiene
- **Location:** `StepsTrader/Views/MomentEntrySheet.swift` (entire file)
- **What:** Good practices observed: `String(localized:comment:)` everywhere, accessibility label/value/hint on the category button, `.presentationDetents([.medium])` (avoids fixed-height clipping for Dynamic Type), `.sensoryFeedback(.warning, trigger:)`, fixed-height warning slot to prevent layout jumps.
- **Why:** Worth recording as a template for new sheets.
- **Action:** None. Reuse pattern.
- **Severity:** N/A

### 8.2 Mixed unit-string concatenation in `GalleryView`
- **Location:** `StepsTrader/Views/GalleryView.swift` (sleep-hours pill, modified region)
- **What:** `"\(model.healthStore.dailySleepHours.formatted(.number.precision(.fractionLength(1))))h"` — the `"h"` suffix is hardcoded.
- **Why:** In some locales the unit symbol goes before the number; the number formatter alone can't fix that.
- **Action:** Use `Measurement<UnitDuration>` with `.formatted()` or a localized format string with positional argument: `String(localized: "\(hours)h", comment: "duration with hours suffix")`.
- **Severity:** Low

### 8.3 `RadialHoldMenu` private subviews lack `// MARK:` and docstrings
- **Location:** `StepsTrader/Views/RadialHoldMenu.swift` (new `RadialCategoryNode`, `RadialMomentNode` private structs)
- **What:** The extracted node views are private with no doc-comment explaining their geometric placement (which is highly visual and not obvious from the code).
- **Why:** Future maintainers reading the file in isolation won't know that `RadialMomentNode` is positioned at angle 0 (right of the arc) vs the category arc at 45°–135°.
- **Action:** Add a one-line `///` doc-comment plus `// MARK:` separators. Cheap.
- **Severity:** Low

### 8.4 Many magic constants throughout the new UI
- **Locations:**
  - `StepsTrader/Views/MomentEntrySheet.swift:209` (`.seconds(3)` warning timer)
  - `StepsTrader/Views/RadialHoldMenu.swift` — `fanRadius`, `momentRadius`, spring response/damping, angle constants
  - `StepsTrader/Services/ShapeIconCache.swift:22-28` (placement tuples), 46 (4% inset), 54/90/161 (`0.48` / `0.5` / `0.45` radius factors), 57 (`0.85 - 0.1 * i` alpha gradient)
- **What:** Animation, geometry, and visual tuning constants are scattered as literals.
- **Why:** Designers re-tuning these have to touch multiple files. The constants also have non-obvious relationships (e.g., body's `0.52` vs heart's `0.34` size factor).
- **Action:** Group into `enum ShapeIconLayout`, `enum RadialMenuLayout`, `enum MomentSheetTiming` namespaces. Comment the visual intent next to each constant.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Two new top-level Markdown notes committed to `main`
- **Locations:**
  - `SWIFTUI_PRO_REVIEW.md` (370 LOC) — looks like the output of the `swiftui-pro` skill.
  - `CircleShapeRendering.md` (285 LOC) — design note for the circle shape generator.
  - Deletion of `TESTFLIGHT_QA.md` (26 LOC) — separate concern, fine to delete.
- **What:** Two large Markdown files added at repo root.
- **Why:** Review outputs and design notes at the repo root pollute the project view. They are also unversioned (no front-matter, no "as of" date), so they'll go stale fast.
- **Action:** Move both to `docs/`, or delete `SWIFTUI_PRO_REVIEW.md` once its actionable items are filed as issues. Decide whether `CircleShapeRendering.md` is canonical design doc (keep, under `docs/design/`) or a one-off note (delete).
- **Severity:** Medium

### 9.2 `skills-lock.json` at repo root
- **Location:** `skills-lock.json` (root)
- **What:** Lock file pinning skill plugin versions (ios-code-audit, swiftui-pro). Mirrors content tracked under `.agents/skills/...`.
- **Why:** If this is meaningful project state, fine. If it's a tooling artefact only relevant to the contributor, it should be in `.gitignore`.
- **Action:** Confirm with the team. Either keep with a short README note or gitignore.
- **Severity:** Low

### 9.3 Unused `AnyTransition.motionSafe()`
- **Location:** `StepsTrader/Utilities/ReduceMotion.swift:49-50`
- **What:** Defined but never referenced anywhere in the codebase.
- **Why:** Dead API surface.
- **Action:** Delete. If the reduce-motion pattern is going to be applied later, file an issue instead.
- **Severity:** Low

### 9.4 `applyCachedSessionState` called twice in the same function
- **Location:** `StepsTrader/Services/AuthenticationService.swift:588-592` and `620-624`
- **What:** Same call, same args, in two branches of `loadStoredSessionAndRefreshUser`. The second occurrence at line 620 is also visually indented inside an `else` that masks its scope.
- **Why:** Future maintainers updating one branch will miss the other.
- **Action:** Hoist the call to a shared point above the try/catch, or factor out a `private func reapplyCachedState(for session:)` helper.
- **Severity:** Low

### 9.5 `OrganicBlobShapeRenderer` ↔ `BlobShapeRenderer` duplication
- **Location:** `StepsTrader/Shapes/OrganicBlobShapeRenderer.swift` and `StepsTrader/Shapes/BlobShapeRenderer.swift`
- **What:** Near-identical center/radius/animation math with slightly different scale constants and wobble frequencies.
- **Why:** Two places to update for every tuning change.
- **Action:** See §7.2 — extract shared kinematics.
- **Severity:** Medium

### 9.6 Pre-existing `// TODO: Migrate to .sensoryFeedback()` comments
- **Locations:** Spread across ~15 files modified by this PR; representative examples — `StepsTrader/Views/CategoryDetailView.swift`, `StepsTrader/Views/PaywallView.swift`, `StepsTrader/Views/SettingsAppearancePage.swift`, plus ~12 others.
- **What:** UIKit haptic generators marked with this TODO. The new `RadialHoldMenu` and `MomentEntrySheet` correctly use `.sensoryFeedback(...)` — the migration is in progress.
- **Why:** Tech debt is visible but unplanned.
- **Action:** Close the migration in one focused PR, or convert all TODOs to a single tracking issue and remove them from code.
- **Severity:** Low

### 9.7 `MomentEntrySheet` is 298 LOC — borderline oversized
- **Location:** `StepsTrader/Views/MomentEntrySheet.swift:1-298`
- **What:** Well-structured (clear `MARK` sections, extracted `MomentCategoryButton`), but at 298 LOC it is right at the threshold.
- **Why:** Not a problem today, but a candidate to split if a similar category-picker is reused elsewhere — extract `MomentCategoryButton` into `Views/Components/`.
- **Action:** No action unless the button is reused; revisit if the file grows.
- **Severity:** Low

### 9.8 `EphemeralMoment` TODO for label sync
- **Location:** `StepsTrader/Models/EphemeralMoment.swift:11`
- **What:** "TODO: sync moment labels via moment_labels JSONB column." See §5.5 — this is the design gap.
- **Why:** Captured under §5.5 as a High; repeating here for the dead-code bucket.
- **Action:** Cross-reference §5.5.
- **Severity:** High (tracked in §5.5)

### 9.9 Inconsistent naming: `preferredBody/Mind/Heart` vs `preferredRest`
- **Location:** `StepsTrader/AppModel.swift` (renamed properties in the PR)
- **What:** Body/heart properties renamed to match category names, but the mind-equivalent retained the `preferredRest` form.
- **Why:** Future readers will wonder which is canonical.
- **Action:** Rename `preferredRestOptions` to `preferredMindOptions` (or document the historical "Rest" branding).
- **Severity:** Low

### 9.10 Bundle-ID and Supabase URL handling
- **Location:** `supabase/functions/send-push/index.ts:127-150`
- **What:** SUPABASE_URL and APNS_BUNDLE_ID read via `Deno.env.get(...)!` / `?? "personal-project.StepsTrader"`. The force-unwrap on SUPABASE_URL/SERVICE_ROLE_KEY would crash the function on cold start if either is missing — that's actually fine for a function (loud failure).
- **Why:** The bundle-ID *fallback* (§6.3) is the bad pattern; not the force-unwraps.
- **Action:** See §6.3.
- **Severity:** Tracked in §6.3.

---

## 10. Cross-cutting recommendations

Patterns worth applying repo-wide rather than one finding at a time:

1. **Service layer should be uniformly `@MainActor`.** `AppModel`, `SubscriptionStore`, `AnnouncementService`, `AuthenticationService` are all `@MainActor`. `SupabaseSyncService` is not — the inconsistency is the source of §3.2. Pick one rule and apply it.
2. **Structured Tasks for post-login work.** §3.1, §3.6, §3.7 are all variants of the same problem: unstructured `Task { … }` that outlives its useful context. Adopt a small `TaskBag` (`Set<Task<...>>`) on services that fire-and-forget, and cancel it on logout / view disappear.
3. **Edge Function security baseline.** The `send-push` function (§6.1, §6.3, §6.4) ships without JWT verification, with an unsafe bundle-ID fallback, and an over-eager token-cleanup heuristic. Establish a standard "Edge Function security checklist" (verify caller role, validate inputs, no PII in errors, scoped CORS) and run all new functions through it.
4. **Session lifecycle hooks.** `signOut` and `deleteAccount` should iterate a single list of registered teardown handlers — push token, RC, cached profile, biometric prompt, etc. Right now (§5.1, §5.2) any new "thing to do on logout" risks being added to one branch and not the other.
5. **Document the optimistic-auth contract.** §5.7, §3.5, §9.4 all reflect the optimistic-cached-state pattern that's worth writing down: "we set `isAuthenticated=true` from cache for any session whose refresh hasn't been definitively rejected." A `Docs/auth-lifecycle.md` ten-liner would prevent the next maintainer from second-guessing the logic.
6. **Magic-constants discipline.** §8.4, §9.6 — animation timings, geometry factors, sleep durations across new UI. Cluster them into per-feature `enum` namespaces with comments.
7. **Server-side moment labels.** §5.5 is the largest *product* risk in this PR — moments lose their human-readable label on reinstall. Either ship the JSONB column with this PR or rewrite the in-sheet copy to reflect single-device persistence.

---

## 11. What was NOT audited

- **Pre-existing code on lines this PR did not touch.** Audit was strictly scoped to PR-changed lines.
- `Steps4Tests/` and `Steps4UITests/` — only flagged true bugs in PR-added test code; no coverage assessment.
- `Dead/`, `Pods/`, `.build/`, `.agents/`, `.claude/` — excluded per skill defaults.
- Algorithmic correctness of `ProceduralShapeGenerator` (called from `ShapeIconCache`, `OrganicBlobShapeRenderer`); only the wrapper layer was reviewed.
- Build settings / Xcode scheme configuration beyond what's visible in `Steps4.xcodeproj/project.pbxproj` deployment-target lines.
- Third-party SPM/CocoaPods dependency internals (`supabase-swift`, RevenueCat).
- StoreKit `.storekit` configuration vs App Store Connect.
- Localization correctness — `Localizable.xcstrings` keys were noted as present but translations not verified.
- iOS-26.1 specific deployment-target target (one of the workspace targets uses 26.1). Compatibility of new code against 26.1's stricter concurrency was not exhaustively traced.
- The Supabase Edge Function was reviewed for security/auth, **not** for correctness of the APNs JWT/payload format under all device states.
- Onboarding flow regressions — the PR touches `OnboardingCoordinator`, `OnboardingFlowView`, `OnboardingStoriesView` etc. Only the diff was read; the full flow was not exercised.
- Push notification entitlements / capabilities in the Xcode project file.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click any `path:line` reference in this report — it should land on the cited line. Each Critical / High finding has an exact line range, not "scattered throughout."

For the Critical / High items, here are the exact lines that prove the claim:

- **§6.1** — open `supabase/functions/send-push/index.ts`, lines `108-115` (only checks `!authHeader`), then `126-134` (service-role client + `select` from `device_tokens` with `eq("platform", "ios")` — **no user filter**), then `97-105` (CORS `Access-Control-Allow-Origin: *`). Critical confirmed.
- **§5.1** — open `StepsTrader/Services/AuthenticationService.swift`, compare `signOut` at lines `132-141` (calls `Task { await SubscriptionStore.shared.logOut() }`) with `deleteAccount` at lines `184-219` — no equivalent call. Confirmed.
- **§5.2** — open `StepsTrader/Services/SupabaseSyncService+DeviceToken.swift`, lines `43-66` — `removeDeviceToken(_:)` is defined. Then `grep -r "removeDeviceToken" StepsTrader/` — the only reference is the definition. Confirmed unreachable.
- **§5.3** — open `StepsTrader/Services/AuthenticationService.swift`, lines `160-164` — `guard http.statusCode < 400 else { return }` after logging; no `self.error = ...`. Caller at line `578` does not check the return. Confirmed.
- **§3.1** — open `StepsTrader/Services/AuthenticationService.swift`, lines `313-321` — `Task { … }` with no `[weak self]` and no stored handle; nothing in `signOut` cancels it.
- **§5.4** — open `StepsTrader/Views/MomentEntrySheet.swift`, lines `219-224` — `model.addMoment(...)` return value discarded (no `let _ =` or `if let moment = ...`), `dismiss()` called unconditionally.
- **§5.5** — open `StepsTrader/Models/EphemeralMoment.swift`, lines `7-12` — TODO comment is explicit about local-only storage.
- **§3.2** — open `StepsTrader/StepsTraderApp.swift`, lines `9-15` — AppDelegate method spawns `Task` with no actor isolation; then `StepsTrader/Services/SupabaseSyncService+DeviceToken.swift`, line `4` shows `extension SupabaseSyncService` with no `@MainActor` annotation, and `StepsTrader/Services/SupabaseSyncService.swift` confirms the base class is not `@MainActor`.
- **§5.6** — open `StepsTrader/Services/ShapeIconCache.swift`, line `63` — `image.cgImage!` force-unwrap.
- **§9.1** — `ls -1 *.md` from repo root shows `SWIFTUI_PRO_REVIEW.md` and `CircleShapeRendering.md` at the top level; both added in this PR per `git diff main...HEAD --name-status`.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.
