# Current Integration / PR #21 — review repairs

Review/fix date: 2026-09-11. Starting integration head: `dc0b0f4d769d3dbce0260634861cdd398f624718`.
PR: https://github.com/Pudan416/step-trader/pull/21.

## Fixed behavior

- Preferences can save the integrated palette categories and Canvas fill settings against production. Daily stats/spend/selections now have version columns; five server triggers reject older writes, including preferences and Canvas.
- Pending Happening additions retain their explicit upsert/delete operation, complete payload and known account owner. Midnight no longer converts absence from today's list into deletion. Legacy raw queue payloads migrate before registration; ambiguous identity-only records never imply a historical deletion. Stale async batch snapshots preserve later tombstones, and another account cannot retag a pending operation.
- Screen Time purchases register nonrepeating intervals ending at the purchased deadline, including short windows and midnight crossings. Legacy callbacks reread the current expiry rather than spending or exhausting a newer purchase. Registration failure preserves/refunds the purchase. App and widget remaining-time displays use the same deadline, and extension purchases preserve exact remaining seconds.
- New native Canvas recipes persist their numeric mesh background. Archive rendering no longer depends on current palette preferences. Old recipes receive a stable fallback when loaded/saved; the original restricted palette cannot be reconstructed because it was never stored.
- Explicit Appearance Apply persists today’s changed native background before Gallery is loaded, while respecting artwork locks and archives. Feeds and chrome use the same saved numeric colors, including Undo-restored artwork.
- Native Canvas editing controls support English and Russian.
- GPU fixtures now exercise current shader behavior: active radial fields, sphere lighting versus invariant gradients, thin contour bands, spatial silhouette differences. Render baselines were refreshed after inspecting captures; tolerances were retained or tightened. The settings catalog includes its actual debug route.
- The 100-remix live-audio test now cooperatively waits for all seven meter taps and audible role/master metrics, with a five-second bound and async cleanup. This removes `RunLoop.run` from its async MainActor context without removing remixes, restarts or graph assertions. The old allocator crash remains a hypothesis until fresh test results; bounded ring sample occupancy is not treated as a monotonic counter.
- `delete-user` is deployed and accepts only authenticated POST for deletion. GET/PUT/DELETE cannot delete an account. Caller-supplied IDs do not select the deletion target.
- Avatar writes/deletes are restricted to the caller's `avatars/{uid}.jpg`; public avatar reads remain available. Authenticated profile updates only permit nickname/country, keeping ban/auth fields administrative.
- `send-push` is deployed with method and service-role authentication guards. Missing/invalid APNs credentials return 503 after authorization instead of crashing the worker on startup. Delivery still requires the deployment's Apple APNs secrets.

## Production deployment record

Project: `molcdgbopchbwcfgiema` (doom ctrl). Inactive development project was not changed.

| Deployment | Applied version |
| --- | --- |
| Schema + stale guards + profile/storage permissions | `20260911201114_repair_integration_sync_and_access` |
| Preserve predeployment offline versions | `20260911202644_preserve_predeployment_sync_versions` |
| delete-user | Edge Function version 1, JWT verification enabled |
| send-push | Edge Function version 2, JWT verification enabled |

The second migration repairs only untouched synthetic `updated_at` values introduced by PostgreSQL's fast column default. It obtains the exact marker from `pg_attribute.attmissingval`, temporarily disables each guard while holding the table lock inside the migration transaction, and substitutes a 1970 baseline. Rows with real client versions are preserved; future INSERT defaults remain `now()`. All five guards remain enabled and zero synthetic marker rows remain after deployment.

These forward migrations reconcile the actual production schema. Older repository and deployed migration histories differ; do not blindly replay old migrations or mark them applied without inspecting their actual effects.

No real user's account or avatar was used for testing. Live smoke tests created anonymous fixtures, checked only their own data/access boundaries, and deleted all fixtures through the deployed account-deletion function. No push broadcasts were sent.

## Validation snapshot at fix authoring

The [PR checks](https://github.com/Pudan416/step-trader/pull/21/checks) record the latest full run. The following evidence preceded publication; it does not claim that later CI or signed-device validation passed.

- `node --test supabase/tests/*.test.mjs`: 13 passing tests; actual TypeScript handlers with mocked side effects.
- `deno check --frozen --lock supabase/deno.lock supabase/functions/delete-user/index.ts supabase/functions/send-push/index.ts`: passed with Deno 2.9.6.
- `python3 Scripts/test_usage_budget_contract.py`: passed; extracts actual budget and extension callback code, stubbing framework side effects.
- `RetryQueueClassificationTests`: 17 passed in a Swift package extracting current production queue code (also scheduled for final XCTest verification).
- Focused simulator regression run: 61 tests passed, including repaired GPU cases, native recipe persistence and all 27 Screen Time cases. Actual DeviceActivity date matching recognizes the backward-padded short interval as current.
- `python3 supabase/tests/live_sync_smoke.py --config /path/to/Secrets.xcconfig`: 47 live checks passed, covering authenticated save/read, cross-account RLS, historical addition replay/delete, stale versions for all five guarded tables, predeployment daily writes, profile column permissions, avatar ownership, function method/auth guards and account cleanup. This script explicitly creates/deletes test fixtures on the configured project; credentials are not printed or committed.
- CI retains xcresult/crash diagnostics and runs Edge Function checks plus the extension callback regression.

The initial 61-test run predates the final no-Gallery Appearance and locked/Undo chrome cases. Their extracted regressions reproduced the bugs then passed after repair; fresh XCTest is required for the final source snapshot. The original full diagnostic binary retains the old audio wait to investigate the allocator crash; no conclusion about that crash is inferred solely from fixture fixes.

## Remaining release validation

- APNs delivery is not verified. Production initially lacked the required bundle configuration; the Apple `.p8` key, Key ID, Team ID, bundle ID and correct sandbox/production environment must be supplied through Supabase Secrets. Unauthorized live POST is 401 and GET is 405 after deployment; these checks do not prove notification delivery.
- Physical-device Screen Time callback timing is not proven by simulator/date tests. Apple delivers callbacks when the device is used, not as an exact-second timer while asleep. Check short purchase, idle across expiry, midnight/custom boundary, extension and monitor-cap/authorization failure on the signed app before release.
- Historical recipes without saved backgrounds cannot recover an unknown old palette restriction. Their fallback may change once during upgrade, then stays stable.
- Ambiguous legacy queue records with no recoverable payload are retained safely; data already discarded by an older app cannot be recreated from IDs alone.
- Existing local data shared across sign-out/sign-in is outside the pending-intent ownership fix; no broad account-state migration was introduced.
- No merge to main or physical-device installation was performed in this repair task.
