# Nowhere — Architecture Review (2026-07-11)

Whole-system review: iOS app + extensions, Supabase (migrations, RLS, edge functions), admin-panel, tg-admin, CI. Complements `CODE_AUDIT.md` (Swift-level findings, re-audited 2026-06-01) — the backend/admin surfaces were explicitly out of that audit's scope and are covered here for the first time.

Severity scale: **release-blocking** (fix before public launch) / **medium** / **minor**. Each finding carries a confidence level.

---

## Executive summary

Nowhere is in better shape than most solo-built products of this scope: a coherent layered client (~40k LOC, 7 targets), 216 unit tests concentrated where the domain risk is (economy, day boundary, budget engine), and admin surfaces with above-typical security hygiene (constant-time compares, webhook secrets, persistent rate limiting). The dominant structural risk is **what lives outside the repo**: the core database schema, RLS policies on the oldest tables, deployment configuration for three backend surfaces, and test-running CI are all unverifiable from version control — and the one production incident to date (the `apple_sub` App Store 2.1(a) rejection) was a direct consequence of exactly that schema drift. The second theme is **client authority without reconciliation**: the economy is computed on-device and synced last-write-wins with no versioning — acceptable for a single-device product today, a wall in front of every multi-device or social feature later. Nothing found is a stop-the-release defect for the current beta posture, but two items (schema-in-repo, the ledger RPC grant) should land before public launch.

## Top 5 structural issues

1. **DB schema source of truth is the live Supabase project, not the repo.** `supabase/migrations/` holds only incremental patches; `users`, `shields`, `daily_selections`, `daily_stats`, `custom_activities`, `saved_routines`, `option_entries` and their RLS policies have no CREATE statements in git. Already caused the `apple_sub NOT NULL` incident (`20260615_fix_users_apple_sub_drop_not_null.sql`). *Release-blocking for public launch. Confidence: high.*
2. **RLS bypass in aggregation RPCs.** `20260216b_add_energy_aggregation_rpcs.sql` defines `sum_energy_delta(p_user_id)` / `count_energy_ledger(p_user_id)` as `SECURITY DEFINER` with EXECUTE granted to `authenticated` — any signed-in user (including anonymous, which the app creates on cold launch) can pass any UUID and read another user's ledger totals, or `NULL` for the global sum. Fix: revoke from `authenticated`, keep `service_role`. Nothing in the shipped app, admin-panel, or tg-admin calls these functions, so the revoke has zero user impact. *Release-blocking (trivial fix, real bypass). Confidence: high for the migration as written; verify deployed grants against the live DB.*
3. **Cross-process App Group state has no write coordination** (CODE_AUDIT §5.2, open). App + DeviceActivityMonitor + ShieldAction + widget read-modify-write the same `UserDefaults(suiteName:)`; race reproduced by `Steps4Tests/AppGroupRMWConcurrencyTests.swift`. Sits under the paid enforcement loop — a lost budget decrement is a correctness bug in the product's core promise. *Medium today (narrow window), rises with scale. Confidence: high.*
4. **Sync is unversioned last-write-wins with heuristic restore.** `SupabaseSyncService` pushes per-table upserts with no `updated_at` conditioning; `restoreFromServer` applies server data "if non-empty"; the offline retry queue replays up-to-3-day-old request bodies verbatim over newer data, and re-queues *all* ≥400 responses (a permanent 400 retries for 3 days). *Medium. Confidence: high on mechanism, medium on user-visible frequency.*
5. **No quality gate in CI, and no staging environment.** No test-running workflow in the repo (only `ci_scripts/ci_post_clone.sh` for Xcode Cloud secret injection; whether tests run is configured invisibly in App Store Connect). `admin-panel/` and `tg-admin/` have zero tests and no lint gate. `Config/Secrets-Debug.xcconfig` and `Secrets-Release.xcconfig` both `#include` the *same* `Secrets.xcconfig`, so debug builds almost certainly talk to production Supabase. *Medium. Confidence: high on repo contents; medium on Xcode Cloud config.*

---

## 1. System model

| Component | Tech | Role | Trust level |
|---|---|---|---|
| iOS app (`StepsTrader/`) | SwiftUI, iOS 17.5+ | All product logic; economy computed on-device | Client-authoritative |
| 4 extensions | FamilyControls / WidgetKit | Enforcement + surfaces; App Group UserDefaults + shared JSON as the bus | Same device |
| Supabase Postgres | 10 incremental migrations, RLS | Mirror/backup of client state + analytics + admin data | Server, per-user RLS |
| 2 Edge Functions | Deno | `delete-user` (self-service, token-derived), `send-push` (bearer-protected, hardened) | service_role |
| admin-panel | Next.js + service_role key | User lookup, ban/unban, stats | Single shared password |
| tg-admin | Cloudflare Worker + service_role key | Same via Telegram; LLM output is display-only, never executed | TG ID allowlist + webhook secret |
| Marketing site | Static (`web/landing/`) | Deployed outside this repo | — |

Client backend access is **hand-rolled Supabase REST** (no supabase-swift): `NetworkClient` (retry/backoff/jitter), `AuthenticationService` (+`SupabaseREST`), `SupabaseSyncService` actor (debounced per-entity tasks, TTL read caches, UserDefaults-persisted offline retry queue). Sessions: Keychain-first with a deliberate UserDefaults fallback shadow for locked-device boot. Only SPM dependency: RevenueCat.

**Open unknowns** (not answerable from the repo):
- Does Xcode Cloud run `Steps4Tests` on every push, or only build?
- Where are admin-panel / tg-admin deployed; how are their secrets rotated?
- Does the deployed DB match the migration files? (No `supabase/config.toml`, no local-dev setup.)
- Who calls `send-push`? (No caller in the repo.)
- Single Supabase project for dev+prod? (xcconfig layering suggests yes.)

---

## 2. Findings by dimension

### 2.1 Domain & modular boundaries — adequate, one god object
- **`AppModel` is a forwarding god-coordinator** (14 extension files, ~3.6k LOC total); `SupabaseSyncService.performFullSync(model:)` reaches back into `AppModel` — infra depends on the UI coordinator's shape. *Medium, high confidence.*
- **Preferences smeared across three storage domains** — `restoreFromServer` writes ~30 keys split between `UserDefaults.standard`, the App Group suite, and hand-mirrored theme keys in both. Every new preference requires remembering domain routing; audit §5.12 was one symptom. Mitigation: a single typed `PreferencesStore`. *Medium, high confidence.*

### 2.2 Data model & persistence — pragmatic locally, fragile at the schema boundary
- **Schema drift** (top issue 1). Mitigation: `supabase db dump --schema public` (+ policies) committed as migration zero; `supabase db diff` for future changes. ~Half a day, eliminates the class.
- **`user_analytics_events` is unbounded**, client-writable with arbitrary `properties` jsonb, no retention. *Minor, high confidence.*
- **Dead end-to-end feature: energy grants.** `energy_ledger` exists; `tg-admin/README.md` documents `/grant` but the command doesn't exist in `tg-admin/src/index.ts`; admin-panel has no grant writer; iOS never reads `energy_ledger` (`serverGrantedSteps` loads only from local UserDefaults, `AppModel+Payment.swift:140`). Three components each implement a third of a feature no path completes. Wire it or delete it. *Minor, high confidence.*

### 2.3 API & integration surfaces — disciplined, but the contract is implicit
- The hand-rolled REST client is good (retry policy with jitter, actor isolation, debounce+dedupe, token refresh). Keeping it over supabase-swift is reasonable — but the **DTO contract exists only as parallel Swift structs and PostgREST column strings**; a renamed column fails silently at decode. Mitigation: check in generated `database.types.ts` as reference + one decode round-trip test per DTO.
- **Retry queue semantics** (top issue 4): `drainRetryQueue()` re-queues any ≥400 (permanent 400s retry for 3 days); replayed stale bodies overwrite fresher rows. Mitigation: drop on 4xx (except 408/429); add `updated_at` conditioning.
- Deep links (`steps-trader://pay?...`) and widget intents are unauthenticated command surfaces — adequately mitigated today (local handoff tokens, reverse-DNS bundleId validation). Keep on the checklist.

### 2.4 Security, privacy, abuse-resistance — strong for the stakes, three gaps
- **RPC grant** (top issue 2) — only true cross-user exposure found. RLS on the six in-repo tables is otherwise correct.
- **Admin panel auth**: single shared password for all admins; session HMAC keyed by the password itself; rate limiting fails open; client IP from a spoofable header; early-return length check is a (marginal) length oracle. Acceptable solo; before a second admin exists, switch to Supabase Auth + `admin` role claim → per-admin identity and audit trail. *Medium, high confidence.*
- **Economy abuse-resistance is zero by design** — steps/sleep/balance are self-reported; `daily_stats` accepts anything. Only the cheater is harmed today. Architectural boundary to enforce: *no feature may read another user's stats until stats have server-side plausibility checks.*
- Positives to keep: hardened `send-push`; token-derived `delete-user`; Keychain-first sessions; Release HTTPS/host assertion in `NetworkClient.swift`; no secrets in git (tracked `Secrets-*.xcconfig` are include-shims — verified).

### 2.5 Reliability, scaling, operational readiness — client resilient; ops invisible
- **§5.2 race** (top issue 3). Design suggestion for the parked decision: move only the *mutable budget/blocking* state into a single JSON file behind a synchronous `Shared/AppGroupStateStore` facade with `NSFileCoordinator`; UserDefaults keeps read-mostly flags; re-arm the existing regression test.
- **Observability is one-way**: OSLog only; no crash reporting, no server-side alerting, no sync-failure telemetry. Before public launch: MetricKit (preferred — no third-party SDK, no privacy-label change; Sentry/Crashlytics would require updating `PrivacyInfo.xcprivacy` and App Store privacy answers) + one `sync_failed` analytics event with error class. *Medium, high confidence.*
- **Shared dev/prod Supabase** (top issue 5): local experiments write production rows. Second free-tier project or Supabase branching + real values in `Secrets-Debug.xcconfig`.
- Scale: fine for years. Watch unbounded analytics and admin `countAuthUsers()` paginating the full auth list per dashboard view.

### 2.6 Developer ergonomics, testing, CI/CD — good instincts, missing the harness
- 216 tests in the right places; gaps: no `SupabaseSyncService` request/decode tests, zero tests in admin-panel/tg-admin, §5.2 regression test disarmed (`XCTSkipIf(true)`).
- No CI gate visible in-repo (top issue 5). ~20-line GitHub Actions workflow: macOS `xcodebuild test` + ubuntu `tsc --noEmit`/lint.
- Hygiene: `.ios-runtime-logs/` xcresult binaries and `.uv-cache/` are git-tracked; `PROJECT_STRATEGY.md` contradicts shipped code ("no StoreKit in repo yet" vs RevenueCat + PaywallView). Stale docs fail silently — like the `/grant` README row.

---

## 3. Architectural options

**A — Contract-hardened status quo (recommended now).** Keep hand-rolled REST, client authority, LWW sync; make every implicit contract explicit (schema baseline, generated types, `updated_at` conditional upserts, retry 4xx semantics, in-repo CI). *Low complexity/risk; leaves multi-device unsolved but stops digging.*

**B — Server-authoritative day ledger (post-beta, data-driven).** Append-only `day_events` (earn/spend, client UUIDs for idempotency), server-derived balance, optimistic local projection offline. Kills the LWW/restore class, enables multi-device, makes grants real, substrate for abuse checks. *Medium-high complexity; only if beta says multi-device/social matters.*

**C — SPM modularization of the client.** Local packages: `NowhereDomain` (pure economy/day-boundary/budget), `NowhereSync`, `NowhereCanvasKit`, `NowhereShared` (App Group contract for all 5 targets). Compile-time boundaries; ends the pbxproj 4-entries-per-file tax for moved code. Pairs with the `@Observable` migration (audit §4.3) as one structural track. *Medium complexity, low risk.*

---

## 4. Remediation roadmap

### Horizon 1 — immediate, before next submission (~1.5–2 days)
1. `REVOKE EXECUTE` on both ledger RPCs from `authenticated`; verify deployed grants against the live DB. *(1–2 h; zero user impact — no client calls them)*
2. Commit full schema + policies as baseline migration; adopt `supabase db diff`. *(3–5 h; describes the live DB, doesn't modify it)*
3. Retry-queue: drop non-retryable 4xx; prune expired before size-truncation (audit §5.13). *(1–2 h)*
4. Delete the `/grant` README claim (or implement end-to-end: ~1 day). *(1 h to delete)*

### Horizon 2 — next release (~8–11 days)
5. §5.2 `Shared/AppGroupStateStore` + re-armed regression test. *(3–4 d, mostly on-device QA of all four extensions — the one item with user-visible regression risk: shield lifting / purchased minutes)*
6. Dev/prod Supabase split + real Debug secrets. *(0.5 d, free tier)*
7. In-repo CI: iOS tests + TS typecheck/lint. *(0.5–1 d)*
8. Crash reporting (MetricKit preferred) + `sync_failed` telemetry. *(1 d)*
9. `updated_at` guard columns + conditional upserts on `daily_*`, preferences, canvases. Additive schema change; must treat "no version supplied" as "accept" so fielded app versions keep syncing. *(1.5–2 d)*

### Horizon 3 — longer-term evolution (post-beta)
10. Decide Option B vs staying client-authoritative, from beta data.
11. SPM modularization + `@Observable` + Swift 6 strict concurrency as one track. *(~2–3 weeks of small PRs)*
12. Admin auth → Supabase Auth roles + admin action audit log (when a second admin appears).
13. Analytics retention policy (e.g., 180-day drop).

**Resources:** Horizons 1+2 ≈ 10–13 working days for one developer; no new headcount; zero new spend (free tiers cover the second Supabase project, CI minutes, MetricKit). UX/data impact: nearly all invisible; the subtle behavior changes (retry drop, conflict resolution) favor the user; §5.2 needs protected device-QA time; crash-reporting choice has a privacy-label implication (avoided by MetricKit).

---

## 5. Design-review checklist

**Schema & contracts**
- [ ] Entire DB (tables, constraints, RLS, triggers, grants) recreatable from the repo alone?
- [ ] Every `SECURITY DEFINER` function: who can EXECUTE, and does it validate `auth.uid()` against its parameters?
- [ ] Machine-checkable contract between client DTOs and server columns?
- [ ] Trigger rewrites checked against constraints from earlier schema generations? (the `apple_sub` lesson)

**State & sync**
- [ ] Each piece of state has exactly one written-down authoritative owner (device / server / extension)?
- [ ] Every cross-process read-modify-write goes through one coordinated accessor?
- [ ] Replayed/queued writes: can a stale body overwrite fresher data? Are non-retryable statuses dropped?
- [ ] Restore-after-reinstall: defined outcome when local and server both hold partial data for *today*?

**Security & abuse**
- [ ] Admin surfaces: per-admin identity, audit trail, rate limiting that fails closed where lockout is safe?
- [ ] Anonymous users: enumerate every RPC and table they can touch.
- [ ] Which client-reported values break which features if forged — documented boundary?
- [ ] URL schemes, widgets, intents, shield actions treated as unauthenticated APIs with listed guards?

**Operations & process**
- [ ] Test gate visible in the repo (not only in a web console)?
- [ ] Can a debug build write to production data?
- [ ] Silent backend failure (edge function, sync): what alerts you? what tells the user?
- [ ] Do README/strategy docs make claims a grep can falsify? Anchor every doc claim to code.
- [ ] Features spanning >1 component: end-to-end proof, not just each third?
